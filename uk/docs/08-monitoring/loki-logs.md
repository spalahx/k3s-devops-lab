# Журнали Loki

Встановлює Loki (сховище журналів) у режимі single-binary і Promtail (відправник журналів) у namespace `monitoring`, а також додає Loki як джерело даних Grafana.

Loki індексує лише мітки (`namespace`, `pod`, `container`, `app`), а не текст журналів, що зменшує використання RAM і диска. Promtail працює як DaemonSet (один pod на вузол), читає файли журналів контейнерів і надсилає їх у Loki.

Передумова: встановлено [Prometheus і Grafana](prometheus-grafana.md).

## 1. Loki

`~/k8s-infrastructure/system/monitoring/loki-values.yaml`:

```yaml
deploymentMode: SingleBinary

loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h
  storage:
    type: filesystem
  limits_config:
    retention_period: 168h
    allow_structured_metadata: true
    volume_enabled: true
  compactor:
    retention_enabled: true
    delete_request_store: filesystem

singleBinary:
  replicas: 1
  resources:
    requests: { cpu: 100m, memory: 256Mi }
    limits:   { memory: 768Mi }
  persistence:
    enabled: true
    storageClass: local-path
    size: 10Gi

# Вимкнути все, що потрібно для розподіленого режиму
gateway:      { enabled: false }
backend:      { replicas: 0 }
read:         { replicas: 0 }
write:        { replicas: 0 }
chunksCache:  { enabled: false }
resultsCache: { enabled: false }
lokiCanary:   { enabled: false }
test:         { enabled: false }
```

| Ключ | Навіщо |
|---|---|
| `deploymentMode: SingleBinary` | Усі компоненти Loki в одному pod'і; достатньо для одного вузла |
| `auth_enabled: false` | Без мультитенантності; Loki доступний лише всередині кластера |
| `storage.type: filesystem` | Чанки зберігаються на PVC, S3 не потрібен |
| `retention_period: 168h` + `compactor.retention_enabled` | Видаляє журнали старші за 7 днів; сам лише ліміт нічого не робить без прапорця compactor'а |
| вимкнені `chunksCache`, `resultsCache`, `lokiCanary`, `test` | Економить сотні МБ RAM на невеликому сервері |

```bash
helm install loki grafana/loki \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/loki-values.yaml \
  --wait --timeout 5m
```

> **Попередження:** якщо версія chart'а, яку ви встановлюєте, відхиляє якийсь ключ вище, порівняйте з `helm show values grafana/loki`; цей файл розрахований на лінійку chart'а 6.x.

## 2. Promtail

`~/k8s-infrastructure/system/monitoring/promtail-values.yaml`:

```yaml
config:
  clients:
    - url: http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push

resources:
  requests: { cpu: 25m, memory: 64Mi }
  limits:   { memory: 128Mi }
```

`loki.monitoring.svc.cluster.local` — це внутрішньокластерне DNS-ім'я сервісу `loki` у namespace `monitoring`.

```bash
helm install promtail grafana/promtail \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/promtail-values.yaml \
  --wait
```

K3s використовує containerd, журнали якого мають формат CRI і лежать у `/var/log/pods/<namespace>_<pod>_<uid>/<container>/*.log`. Типова конфігурація збору в chart'і монтує `/var/log/pods` і розбирає формат CRI, тому змінювати шляхи не потрібно. Коригуйте монтування лише якщо K3s запущено з нестандартним `--data-dir` або каталогом журналів.

> **Попередження:** Promtail перебуває в режимі підтримки; його наступник — Grafana Alloy. Promtail усе ще працює з наведеним вище chart'ом і є найпростішим варіантом на одному вузлі.

## 3. Додавання Loki до Grafana

Додайте під `grafana:` у `kube-prometheus-stack-values.yaml`:

```yaml
grafana:
  # ...наявні ключі...
  additionalDataSources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki.monitoring.svc.cluster.local:3100
```

Застосуйте:

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

Швидка альтернатива без Helm: Grafana > Connections > Data sources > Add > Loki, URL `http://loki.monitoring.svc.cluster.local:3100`, Save & test. Налаштування зберігається на PVC Grafana, але втрачається при чистому перевстановленні.

Необов'язковий дашборд журналів: Dashboards > New > Import, ID `13639`, джерело даних `Loki`.

## 4. Приклади LogQL

Grafana > Explore > джерело даних `Loki`. Запит завжди починається з селектора міток; фільтри після нього необов'язкові.

| Запит | Результат |
|---|---|
| `{namespace="<PROJECT_NAME>"}` | Усі журнали namespace |
| `{namespace="<PROJECT_NAME>", pod=~"app-.*"}` | Pod'и, ім'я яких відповідає регулярному виразу |
| `{namespace="<PROJECT_NAME>", container="mysql"}` | Один контейнер |
| `{namespace="<PROJECT_NAME>"} \|= "error"` | Рядки, що містять `error` |
| `{namespace="<PROJECT_NAME>"} \|~ "(?i)fatal\|exception"` | Регулярний вираз без урахування регістру |
| `{namespace="<PROJECT_NAME>"} != "healthcheck"` | Рядки без `healthcheck` |
| `{namespace="monitoring"}` | Журнали самого стека моніторингу |
| `sum by (pod) (rate({namespace="<PROJECT_NAME>"} \|= "error" [5m]))` | Частота помилок по pod'ах |
| `sum by (namespace) (count_over_time({namespace=~".+"}[1h]))` | Обсяг журналів по namespace |

Оператори: `\|=` містить, `!=` не містить, `\|~` збігається з регулярним виразом, `!~` не збігається з регулярним виразом. (У таблицях Markdown вертикальна риска екранується як `\|`; у Grafana вводьте звичайну `|`.)

## Зберігання та диск

- Журнали видаляються після `retention_period` (вище 7 днів) compactor'ом, який запускається приблизно кожні 10 хвилин.
- Розмір PVC (10Gi) має покривати `retention_period`, помножений на добовий обсяг журналів; перевірте використання:
  ```bash
  kubectl -n monitoring exec loki-0 -c loki -- df -h /var/loki
  ```
- Обсяг переважно створюють «балакучі» застосунки (debug-журналювання, журнали доступу); виключайте шум за допомогою `!=` у запитах і виправляйте його в джерелі.

## Перевірка

```bash
helm list -n monitoring                                   # loki, prometheus, promtail: deployed
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki       # Running, 2/2 (разом із sidecar)
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail   # по одному на вузол, Running
kubectl get pvc -n monitoring                             # усі Bound
```

Grafana > Connections > Data sources > Loki > Save & test показує зелене повідомлення. Запит `{namespace="monitoring"}` в Explore повертає рядки.

## Усунення проблем із порожніми журналами

| Перевірка | Команда / дія |
|---|---|
| Promtail запущено | `kubectl -n monitoring get pods -l app.kubernetes.io/name=promtail` |
| Помилки Promtail (connection refused, 429, 400) | `kubectl -n monitoring logs ds/promtail --tail=50` |
| Loki доступний із кластера | `kubectl -n monitoring run curl --rm -it --image=curlimages/curl --restart=Never -- curl -s http://loki:3100/ready` має вивести `ready` (після старту може знадобитися близько 15 с) |
| Мітки існують | Explore > Label browser; використовуйте лише наведені значення `namespace` |
| Часовий діапазон | Встановіть в Explore "Last 15 minutes"; перші рядки з'являються протягом хвилини |
| Файли, видимі для Promtail | `kubectl -n monitoring exec ds/promtail -- ls /var/log/pods` має показати каталоги pod'ів |
| Loki відхиляє старі рядки | `reject_old_samples` відкидає записи старші за тиждень; для свіжих журналів неактуально |
| Loki `CrashLoopBackOff` | `kubectl -n monitoring logs loki-0 -c loki`; зазвичай помилка YAML/схеми у values або надто низький ліміт пам'яті |
| Тест джерела даних не проходить | URL має бути точно `http://loki.monitoring.svc.cluster.local:3100`, без додаткового шляху |

Далі: [Глосарій](../99-appendix/glossary.md)
