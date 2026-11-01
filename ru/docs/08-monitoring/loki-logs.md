# Логи в Loki

Устанавливает Loki (хранилище логов) в режиме single-binary и Promtail (сборщик логов) в namespace `monitoring` и добавляет Loki как источник данных в Grafana.

Loki индексирует только метки (`namespace`, `pod`, `container`, `app`), а не текст логов, поэтому расходует мало RAM и диска. Promtail работает как DaemonSet (один под на узел), читает файлы логов контейнеров и отправляет их в Loki.

Требование: установлены [Prometheus и Grafana](prometheus-grafana.md).

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

# Отключаем всё, что нужно распределённому режиму
gateway:      { enabled: false }
backend:      { replicas: 0 }
read:         { replicas: 0 }
write:        { replicas: 0 }
chunksCache:  { enabled: false }
resultsCache: { enabled: false }
lokiCanary:   { enabled: false }
test:         { enabled: false }
```

| Ключ | Зачем |
|---|---|
| `deploymentMode: SingleBinary` | Все компоненты Loki в одном поде; для одного узла достаточно |
| `auth_enabled: false` | Без мультитенантности; Loki доступен только внутри кластера |
| `storage.type: filesystem` | Данные пишутся в PVC, S3 не нужен |
| `retention_period: 168h` + `compactor.retention_enabled` | Удаляет логи старше 7 дней; один лимит без флага compactor ничего не делает |
| `chunksCache`, `resultsCache`, `lokiCanary`, `test` выключены | Экономят сотни МБ RAM на небольшом сервере |

```bash
helm install loki grafana/loki \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/loki-values.yaml \
  --wait --timeout 5m
```

> **Warning:** Если установленная версия chart отвергает какой-либо ключ, сверьтесь с `helm show values grafana/loki`; файл написан для линейки chart 6.x. Эталонный сервер работает на chart 7.3.0 (Loki 3.6.12) с той же схемой `SingleBinary`; всё равно сверьте ключи с `helm show values grafana/loki` перед установкой.

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

`loki.monitoring.svc.cluster.local` это внутреннее DNS-имя сервиса `loki` в namespace `monitoring`.

```bash
helm install promtail grafana/promtail \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/promtail-values.yaml \
  --wait
```

K3s использует containerd, чьи логи лежат в формате CRI в `/var/log/pods/<namespace>_<pod>_<uid>/<container>/*.log`. Конфигурация chart по умолчанию монтирует `/var/log/pods` и разбирает формат CRI, поэтому менять пути не нужно. Правьте монтирования, только если K3s запущен с нестандартным `--data-dir` или каталогом логов.

> **Warning:** Promtail объявлен устаревшим в пользу Grafana Alloy; перед использованием в новой установке проверьте статус проекта. Эталонный сервер работает с Loki без какого-либо сборщика логов, поэтому шаги с Promtail на этой странице не проверялись на реальном железе. Для новой установки лучше Alloy.

## 3. Добавление Loki в Grafana

Добавьте в секцию `grafana:` файла `kube-prometheus-stack-values.yaml`:

```yaml
grafana:
  # ...существующие ключи...
  additionalDataSources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki.monitoring.svc.cluster.local:3100
```

Примените:

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

Быстрая альтернатива без Helm: Grafana > Connections > Data sources > Add > Loki, URL `http://loki.monitoring.svc.cluster.local:3100`, Save & test. Источник сохраняется в PVC Grafana, но пропадёт при переустановке с нуля.

Опциональный дашборд логов: Dashboards > New > Import, ID `13639`, источник `Loki`.

## 4. Примеры LogQL

Grafana > Explore > источник `Loki`. Запрос всегда начинается с селектора меток; фильтры после него необязательны.

| Запрос | Результат |
|---|---|
| `{namespace="<PROJECT_NAME>"}` | Все логи namespace |
| `{namespace="<PROJECT_NAME>", pod=~"app-.*"}` | Поды, имя которых подходит под regex |
| `{namespace="<PROJECT_NAME>", container="mysql"}` | Один контейнер |
| `{namespace="<PROJECT_NAME>"} \|= "error"` | Строки, содержащие `error` |
| `{namespace="<PROJECT_NAME>"} \|~ "(?i)fatal\|exception"` | Regex без учёта регистра |
| `{namespace="<PROJECT_NAME>"} != "healthcheck"` | Строки без `healthcheck` |
| `{namespace="monitoring"}` | Логи самого стека мониторинга |
| `sum by (pod) (rate({namespace="<PROJECT_NAME>"} \|= "error" [5m]))` | Частота ошибок по подам |
| `sum by (namespace) (count_over_time({namespace=~".+"}[1h]))` | Объём логов по namespace |

Операторы: `\|=` содержит, `!=` не содержит, `\|~` совпадает с regex, `!~` не совпадает с regex. (В таблицах Markdown вертикальная черта экранирована как `\|`; в Grafana вводите обычный `|`.)

## Хранение и диск

- Логи удаляются спустя `retention_period` (выше 7 дней) компактором, который запускается примерно каждые 10 минут.
- Размер PVC (10Gi) должен покрывать `retention_period`, умноженный на суточный объём логов; проверка заполнения:
  ```bash
  kubectl -n monitoring exec loki-0 -c loki -- df -h /var/loki
  ```
- Основной объём дают многословные приложения (debug-логи, access-логи); шум скрывайте через `!=` в запросах и устраняйте в источнике.

## Verify

```bash
helm list -n monitoring                                   # loki, prometheus, promtail: deployed
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki       # Running, 2/2 (вместе с sidecar)
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail   # по одному на узел, Running
kubectl get pvc -n monitoring                             # все Bound
```

Grafana > Connections > Data sources > Loki > Save & test показывает зелёное сообщение. Запрос `{namespace="monitoring"}` в Explore возвращает строки.

## Диагностика пустых логов

| Проверка | Команда / действие |
|---|---|
| Promtail запущен | `kubectl -n monitoring get pods -l app.kubernetes.io/name=promtail` |
| Ошибки Promtail (connection refused, 429, 400) | `kubectl -n monitoring logs ds/promtail --tail=50` |
| Loki доступен из кластера | `kubectl -n monitoring run curl --rm -it --image=curlimages/curl --restart=Never -- curl -s http://loki:3100/ready` должен вывести `ready` (после старта может потребоваться около 15 с) |
| Метки существуют | Explore > Label browser; используйте только перечисленные значения `namespace` |
| Временной диапазон | Установите в Explore "Last 15 minutes"; первые строки появляются в течение минуты |
| Файлы видны Promtail | `kubectl -n monitoring exec ds/promtail -- ls /var/log/pods` должен показать каталоги подов |
| Loki отвергает старые строки | `reject_old_samples` отбрасывает записи старше недели; для свежих логов не актуально |
| Loki в `CrashLoopBackOff` | `kubectl -n monitoring logs loki-0 -c loki`; обычно ошибка YAML/схемы в values или слишком низкий лимит памяти |
| Тест источника данных не проходит | URL должен быть ровно `http://loki.monitoring.svc.cluster.local:3100`, без пути на конце |

Next: [Глоссарий](../99-appendix/glossary.md)
