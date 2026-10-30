# Prometheus и Grafana

Устанавливает `kube-prometheus-stack` (Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics) в namespace `monitoring`, настроенный для небольшого одноузлового сервера K3s, с Grafana, опубликованной через Traefik по адресу `grafana.<DOMAIN_BASE>`.

| Компонент | Роль |
|---|---|
| Prometheus | Собирает и хранит метрики (числа во времени) |
| Alertmanager | Маршрутизирует оповещения, сработавшие по правилам Prometheus |
| node-exporter | Метрики хоста: CPU, RAM, диск, сеть (один под на узел) |
| kube-state-metrics | Состояние объектов Kubernetes: фазы подов, перезапуски, deployments |
| Grafana | Дашборды поверх Prometheus (и Loki, см. следующий документ) |

Требования: выполнены [основы Helm](helm-basics.md); `kubectl get storageclass` показывает `local-path` (идёт с K3s; данные лежат в `/var/lib/rancher/k3s/storage/` и переживают перезагрузку); свободно не менее 2 ГБ RAM (`free -h`, колонка `available`).

## 1. Пароль администратора Grafana

`<GRAFANA_ADMIN_PASSWORD>` это пароль, который вы выбираете для пользователя `admin` в Grafana. Храните его в Secret, чтобы он не попал в Git:

```bash
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<GRAFANA_ADMIN_PASSWORD>'
```

## 2. Values-файл

`~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    retention: 7d
    retentionSize: 8GB
    resources:
      requests: { cpu: 100m, memory: 400Mi }
      limits:   { memory: 1Gi }
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi

alertmanager:
  alertmanagerSpec:
    resources:
      requests: { cpu: 10m, memory: 32Mi }
      limits:   { memory: 128Mi }
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 1Gi

grafana:
  admin:
    existingSecret: grafana-admin
    userKey: admin-user
    passwordKey: admin-password
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits:   { memory: 384Mi }
  persistence:
    enabled: true
    type: pvc
    storageClassName: local-path
    accessModes: ["ReadWriteOnce"]
    size: 2Gi
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/router.tls: "true"
    hosts:
      - grafana.<DOMAIN_BASE>
    path: /
  # Источник данных Loki добавляется в следующем документе

# K3s запускает эти компоненты внутри одного процесса и не отдаёт их метрики;
# при включении появляются постоянные алерты "target down".
kubeEtcd:              { enabled: false }
kubeControllerManager: { enabled: false }
kubeScheduler:         { enabled: false }
kubeProxy:             { enabled: false }

prometheusOperator:
  resources:
    requests: { cpu: 20m, memory: 64Mi }
    limits:   { memory: 200Mi }
kube-state-metrics:
  resources:
    requests: { cpu: 10m, memory: 32Mi }
    limits:   { memory: 128Mi }
prometheus-node-exporter:
  resources:
    requests: { cpu: 10m, memory: 16Mi }
    limits:   { memory: 64Mi }
```

| Ключ | Зачем |
|---|---|
| `retention` + `retentionSize` | Prometheus удаляет данные старше лимита по времени или сверх лимита по размеру, что наступит раньше; держите `retentionSize` ниже размера PVC (около 80%) |
| `storageClassName: local-path` | Без PVC метрики теряются при каждом перезапуске пода |
| лимиты `memory` | Ограничивают RAM, чтобы всплеск кардинальности не вытеснил проекты на том же узле |
| `grafana.ingress.hosts` | Должен совпадать с именем, которое вы открываете в браузере, иначе Traefik вернёт 404 |
| `kube*: enabled: false` | Особенность K3s, см. комментарий в файле |

## 3. Установка

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

Имя релиза `prometheus` становится префиксом всех объектов, например сервис Grafana называется `prometheus-grafana`.

## 4. Доступ к Grafana

1. Создайте DNS-запись `grafana.<DOMAIN_BASE>` на `<SERVER_IP>` или, для работы только в локальной сети, добавьте на клиентской машине в `/etc/hosts`:
   ```
   <SERVER_IP>   grafana.<DOMAIN_BASE>
   ```
2. Откройте `https://grafana.<DOMAIN_BASE>`. Предупреждение браузера о самоподписанном сертификате Traefik ожидаемо, если не настроен настоящий сертификат.
3. Войдите как `admin` с паролем `<GRAFANA_ADMIN_PASSWORD>`.

Нет DNS? Используйте port-forward вместо ingress:

```bash
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
# http://localhost:3000
```

Узнать забытый пароль:

```bash
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

> **Warning:** После первого запуска пароль сохраняется в базе Grafana. Изменение Secret позже его не меняет; используйте `kubectl -n monitoring exec deploy/prometheus-grafana -c grafana -- grafana cli admin reset-admin-password '<NEW_PASSWORD>'`.

## 5. Дашборды

Chart ставит готовые дашборды (меню Dashboards):

| Дашборд | Что показывает |
|---|---|
| Kubernetes / Compute Resources / Cluster | CPU и RAM всего кластера |
| Kubernetes / Compute Resources / Namespace (Pods) | Потребление по namespace; сравнивайте namespace проектов с `monitoring` |
| Kubernetes / Compute Resources / Pod | Один под, по контейнерам |
| Node Exporter / Nodes | CPU, память, диск и сеть хоста |

Дополнительные дашборды сообщества: Dashboards > New > Import, введите ID, выберите источник `Prometheus`.

| ID | Название |
|---|---|
| 1860 | Node Exporter Full |
| 15757 | Kubernetes / Views / Global |
| 15760 | Kubernetes / Views / Pods |

## 6. Ключевые запросы PromQL

Выполняйте в Explore с источником `Prometheus`.

| Цель | Запрос |
|---|---|
| Загрузка CPU узла, % | `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| Использование RAM узла, % | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` |
| Заполнение корневого диска, % | `(1 - node_filesystem_avail_bytes{mountpoint="/",fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="tmpfs"}) * 100` |
| Память подов по namespace | `sum by (namespace) (container_memory_working_set_bytes{container!=""})` |
| CPU подов (ядра) в namespace | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="<PROJECT_NAME>",container!=""}[5m]))` |
| Поды не в Running | `sum by (namespace, phase) (kube_pod_status_phase{phase=~"Pending\|Failed\|Unknown"} == 1)` |
| Перезапуски контейнеров за 1 ч | `increase(kube_pod_container_status_restarts_total[1h]) > 0` |
| Недоступные цели сбора | `up == 0` |

## 7. Обновление и удаление

```bash
helm repo update
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

```bash
helm uninstall prometheus -n monitoring
kubectl -n monitoring delete pvc -l app.kubernetes.io/name=grafana   # опционально: удалит дашборды
kubectl -n monitoring delete pvc -l operator.prometheus.io/name=prometheus-kube-prometheus-prometheus   # опционально: удалит метрики
```

> **Warning:** При обновлении на новую мажорную версию chart могут потребоваться обновления CRD, которые Helm не применяет автоматически; перед скачком мажорной версии прочитайте upgrade notes chart.

## Verify

```bash
kubectl get pods -n monitoring        # все Running, счётчики готовности совпадают (например 2/2)
kubectl get pvc -n monitoring         # все Bound
kubectl get ingress -n monitoring     # host grafana.<DOMAIN_BASE>
```

В Grafana: Explore > `Prometheus` > запрос `up` возвращает ряды со значением `1`. Первые 2-3 минуты после установки графики пустые.

| Симптом | Решение |
|---|---|
| PVC в `Pending` | Нет StorageClass по умолчанию; `kubectl get storageclass` должен показывать `local-path` |
| Под `OOMKilled` / `CrashLoopBackOff` | `kubectl describe pod -n monitoring <POD>`; увеличьте лимит памяти или уменьшите `retention` |
| 404 от Traefik | Host в Ingress не совпадает с используемым URL; проверьте `kubectl get ingress -n monitoring` |

Next: [Логи в Loki](loki-logs.md)
