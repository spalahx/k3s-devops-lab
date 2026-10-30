# Ollama в отдельном namespace

Запускает Ollama (среду выполнения локальных LLM вроде `llama3` или `mistral`) в собственном namespace K3s `ai-models` с жёсткими лимитами CPU/RAM, чтобы инференс не отбирал ресурсы у веб-проектов на том же узле. Опционально; пропустите на серверах с RAM менее ~8 ГБ или если используется внешний LLM API. Инференс здесь только на CPU.

Манифесты лежат в `~/k8s-infrastructure/ai-models/`.

## 1. Namespace и квота

```bash
mkdir -p ~/k8s-infrastructure/ai-models && cd ~/k8s-infrastructure/ai-models
kubectl create namespace ai-models
```

`ai-resource-quota.yaml` (потолок на весь namespace, независимо от настроек отдельных pod):

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ai-models-quota
  namespace: ai-models
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "3"
    limits.memory: 6Gi
    persistentvolumeclaims: "1"
    requests.storage: 40Gi
```

```bash
kubectl apply -f ai-resource-quota.yaml
```

Подберите значения под машину: например, на узле с 16 ГБ, где веб-проектам нужно 8-10 ГБ, отдавайте `ai-models` не более 4-6 ГБ. Когда квота покрывает CPU/память, каждый pod в namespace обязан указывать requests и limits, иначе он будет отклонён.

## 2. Deployment, хранилище, Service

Модели весят 2-40 ГБ и не входят в образ, поэтому нужно постоянное хранилище. В K3s есть StorageClass `local-path`, создающий PVC на диске узла.

`ollama.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ollama-data
  namespace: ai-models
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: 30Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
  namespace: ai-models
spec:
  replicas: 1
  strategy:
    type: Recreate          # том RWO: старый pod должен остановиться до запуска нового
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
    spec:
      containers:
        - name: ollama
          image: ollama/ollama:0.5.7   # зафиксируйте актуальный релиз вместо :latest
          ports:
            - containerPort: 11434
          env:
            - name: OLLAMA_KEEP_ALIVE
              value: "5m"               # выгружать модель из RAM после 5 минут простоя
            - name: OLLAMA_NUM_PARALLEL
              value: "1"
            - name: OLLAMA_MAX_LOADED_MODELS
              value: "1"
          resources:
            requests:
              cpu: "1"
              memory: 2Gi
            limits:
              cpu: "2"
              memory: 5Gi
          volumeMounts:
            - name: ollama-data
              mountPath: /root/.ollama
          readinessProbe:
            httpGet:
              path: /
              port: 11434
            initialDelaySeconds: 5
      volumes:
        - name: ollama-data
          persistentVolumeClaim:
            claimName: ollama-data
---
apiVersion: v1
kind: Service
metadata:
  name: ollama
  namespace: ai-models
spec:
  selector:
    app: ollama
  ports:
    - port: 11434
      targetPort: 11434
```

```bash
kubectl apply -f ollama.yaml
kubectl -n ai-models get pods -w
```

| Параметр | Зачем |
|---|---|
| `requests` / `limits` | `requests` — гарантированный минимум для планировщика; `limits` — потолок (CPU притормаживается, при превышении памяти pod убивается по OOM). `limits.memory` должен быть больше размера модели |
| PVC на `/root/.ollama` | Без него каждый перезапуск pod заново скачивает все модели |
| `strategy: Recreate` | Том `ReadWriteOnce` нельзя смонтировать в два pod при rolling update |
| `OLLAMA_KEEP_ALIVE` | Освобождает RAM для других нагрузок в простое |

## 3. Скачать модель

Выберите модель под лимит памяти (7-8B с 4-битной квантизацией нужно около 5 ГБ; модели класса 3B помещаются в меньший объём):

```bash
kubectl -n ai-models exec -it deployment/ollama -- ollama pull llama3.2:3b
kubectl -n ai-models exec -it deployment/ollama -- ollama list
```

## 4. Доступ

Service имеет тип `ClusterIP`: доступен только внутри кластера по адресу

```
http://ollama.ai-models.svc.cluster.local:11434
```

Pod из любого namespace может обращаться к нему без дополнительной настройки. С ноутбука используйте туннель, а не Ingress:

```bash
kubectl -n ai-models port-forward svc/ollama 11434:11434
```

> **Warning:** у Ollama нет аутентификации. Не публикуйте её через Ingress или открытый порт без слоя авторизации перед ней (например, basic-auth middleware в Traefik).

## 5. Вызов API

Изнутри кластера:

```bash
kubectl run curl-test -n default --rm -it --restart=Never --image=curlimages/curl -- \
  curl -s http://ollama.ai-models.svc.cluster.local:11434/api/generate \
  -d '{"model": "llama3.2:3b", "prompt": "Say hello in one sentence.", "stream": false}'
```

Через port-forward с ноутбука:

```bash
curl -s localhost:11434/api/chat -d '{
  "model": "llama3.2:3b",
  "messages": [{"role": "user", "content": "Hello"}],
  "stream": false
}'
```

## Verify

```bash
kubectl -n ai-models get pods,pvc
kubectl -n ai-models describe resourcequota ai-models-quota
kubectl -n ai-models top pod        # нужен metrics-server (входит в K3s)
```

Во время генерации веб-проекты в других namespace должны отвечать быстро (следите в Grafana, см. [Prometheus и Grafana](../08-monitoring/prometheus-grafana.md)).

## Gotchas

| Симптом | Причина / решение |
|---|---|
| Pod в `Pending` | requests превышают квоту или свободные ресурсы узла; уменьшите `requests` или увеличьте квоту. Смотрите `kubectl describe pod` |
| `OOMKilled` | Модель больше `limits.memory`; увеличьте лимит или выберите меньшую/более квантованную модель |
| `forbidden: failed quota ... must specify limits` | У pod в `ai-models` нет requests/limits (квота их требует) |
| Модели скачиваются заново после перезапуска | PVC не смонтирован в `/root/.ollama` |
| Очень медленные ответы | Инференс только на CPU; берите модели поменьше и держите `limits.cpu` в пределах того, что узел может отдать |
| Сайты тормозят во время инференса | Квота слишком щедрая; уменьшите `limits.cpu` / `limits.memory` |

Next: [Чек-лист roadmap](../99-appendix/roadmap-checklist.md)
