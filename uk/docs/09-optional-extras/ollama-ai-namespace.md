# Ollama в окремому namespace

Запускає Ollama (середовище виконання локальних LLM, як-от `llama3` або `mistral`) у власному namespace K3s `ai-models` із жорсткими обмеженнями CPU/RAM, щоб інференс не віднімав ресурси в вебпроєктів на тому самому вузлі. Необов'язково; пропустіть на серверах із менш ніж близько 8 ГБ RAM або коли натомість використовується хмарний API LLM. Інференс тут лише на CPU.

Маніфести лежать у `~/k8s-infrastructure/ai-models/`.

## 1. Namespace і квота

```bash
mkdir -p ~/k8s-infrastructure/ai-models && cd ~/k8s-infrastructure/ai-models
kubectl create namespace ai-models
```

`ai-resource-quota.yaml` (стеля для всього namespace, незалежна від налаштувань окремих pod'ів):

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

Підберіть числа під свою машину: наприклад, на вузлі з 16 ГБ, де вебпроєктам потрібно 8-10 ГБ, віддайте `ai-models` не більше 4-6 ГБ. Коли квота охоплює CPU/пам'ять, кожен pod у namespace має оголосити requests і limits, інакше його буде відхилено.

## 2. Deployment, сховище, Service

Моделі займають 2-40 ГБ і не входять до образу, тому їм потрібне постійне сховище. K3s постачається зі StorageClass `local-path`, який створює PVC на диску вузла.

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
    type: Recreate          # RWO-том: старий pod має зупинитися, перш ніж стартує новий
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
          image: ollama/ollama:0.5.7   # зафіксуйте актуальний реліз замість :latest
          ports:
            - containerPort: 11434
          env:
            - name: OLLAMA_KEEP_ALIVE
              value: "5m"               # вивантажити модель з RAM після 5 хвилин простою
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

| Налаштування | Навіщо |
|---|---|
| `requests` / `limits` | `requests` — зарезервований мінімум, що використовується для планування; `limits` — стеля (CPU обмежується, а при перевищенні пам'яті pod завершується через OOM). `limits.memory` має перевищувати розмір моделі |
| PVC на `/root/.ollama` | Без нього кожен перезапуск pod'а знову завантажує всі моделі |
| `strategy: Recreate` | Том `ReadWriteOnce` не можуть змонтувати два pod'и під час послідовного оновлення (rolling update) |
| `OLLAMA_KEEP_ALIVE` | Звільняє RAM для інших навантажень у простої |

## 3. Завантаження моделі

Оберіть модель, що вкладається в ліміт пам'яті (модель 7-8B із 4-бітним квантуванням потребує близько 5 ГБ; моделі класу 3B вміщаються в менше):

```bash
kubectl -n ai-models exec -it deployment/ollama -- ollama pull llama3.2:3b
kubectl -n ai-models exec -it deployment/ollama -- ollama list
```

## 4. Доступ ззовні

Service має тип `ClusterIP`: доступний лише всередині кластера за адресою

```
http://ollama.ai-models.svc.cluster.local:11434
```

Pod'и в будь-якому namespace можуть звертатися до нього без додаткового налаштування. З ноутбука використовуйте тунель, а не Ingress:

```bash
kubectl -n ai-models port-forward svc/ollama 11434:11434
```

> **Попередження:** Ollama не має автентифікації. Не відкривайте його через Ingress або публічний порт без шару автентифікації перед ним (наприклад, middleware basic-auth у Traefik).

## 5. Виклик API

Зсередини кластера:

```bash
kubectl run curl-test -n default --rm -it --restart=Never --image=curlimages/curl -- \
  curl -s http://ollama.ai-models.svc.cluster.local:11434/api/generate \
  -d '{"model": "llama3.2:3b", "prompt": "Say hello in one sentence.", "stream": false}'
```

Через port-forward з ноутбука:

```bash
curl -s localhost:11434/api/chat -d '{
  "model": "llama3.2:3b",
  "messages": [{"role": "user", "content": "Hello"}],
  "stream": false
}'
```

## Перевірка

```bash
kubectl -n ai-models get pods,pvc
kubectl -n ai-models describe resourcequota ai-models-quota
kubectl -n ai-models top pod        # потребує metrics-server (входить до K3s)
```

Під час генерації вебпроєкти в інших namespace мають залишатися чутливими (стежте за цим у Grafana, див. [Prometheus і Grafana](../08-monitoring/prometheus-grafana.md)).

## Типові проблеми

| Симптом | Причина / виправлення |
|---|---|
| Pod `Pending` | Requests перевищують квоту або вільну місткість вузла; зменште `requests` або збільште квоту. Перевірте `kubectl describe pod` |
| `OOMKilled` | Модель більша за `limits.memory`; збільште ліміт або оберіть меншу/сильніше квантовану модель |
| `forbidden: failed quota ... must specify limits` | У pod'а в `ai-models` немає requests/limits (квота їх вимагає) |
| Моделі завантажуються повторно після перезапуску | PVC не змонтовано в `/root/.ollama` |
| Дуже повільні відповіді | Інференс лише на CPU; використовуйте менші моделі та тримайте `limits.cpu` на рівні, який вузол може віддати |
| Сайти гальмують під час інференсу | Квота занадто щедра; зменште `limits.cpu` / `limits.memory` |

Далі: [Контрольний список дорожньої карти](../99-appendix/roadmap-checklist.md)
