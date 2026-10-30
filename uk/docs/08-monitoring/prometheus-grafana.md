# Prometheus і Grafana

Встановлює `kube-prometheus-stack` (Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics) у namespace `monitoring`, налаштований для невеликого одновузлового сервера K3s, з Grafana, відкритою через Traefik за адресою `grafana.<DOMAIN_BASE>`.

| Компонент | Роль |
|---|---|
| Prometheus | Збирає та зберігає метрики (числа в часі) |
| Alertmanager | Маршрутизує сповіщення, що спрацювали за правилами Prometheus |
| node-exporter | Метрики хоста: CPU, RAM, диск, мережа (один pod на вузол) |
| kube-state-metrics | Стан об'єктів Kubernetes: фази pod'ів, перезапуски, Deployment'и |
| Grafana | Дашборди над Prometheus (і Loki, див. наступний документ) |

Передумови: виконано [Основи Helm](helm-basics.md); `kubectl get storageclass` показує `local-path` (постачається з K3s; дані лежать у `/var/lib/rancher/k3s/storage/` і переживають перезавантаження); щонайменше 2 ГБ вільної RAM (`free -h`, стовпець `available`).

## 1. Пароль адміністратора Grafana

`<GRAFANA_ADMIN_PASSWORD>` — це пароль, який ви обираєте для користувача Grafana `admin`. Збережіть його в Secret, щоб він ніколи не потрапив у Git:

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
  # Джерело даних Loki додається в наступному документі

# K3s запускає ці компоненти в одному процесі та не віддає їхні метрики;
# якщо залишити їх увімкненими, з'являтимуться постійні сповіщення "target down".
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

| Ключ | Навіщо |
|---|---|
| `retention` + `retentionSize` | Prometheus видаляє дані, старші за ліміт часу або понад ліміт розміру, залежно від того, що настане раніше; тримайте `retentionSize` нижче розміру PVC (близько 80%) |
| `storageClassName: local-path` | Без PVC метрики втрачаються після кожного перезапуску pod'а |
| ліміти `memory` | Обмежують RAM, щоб сплеск кардинальності не залишив без пам'яті проєкти на тому самому вузлі |
| `grafana.ingress.hosts` | Має збігатися з іменем хоста, яке ви відкриваєте в браузері, інакше Traefik поверне 404 |
| `kube*: enabled: false` | Специфічно для K3s, див. коментар у файлі |

## 3. Встановлення

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

Назва release'у `prometheus` стає префіксом усіх об'єктів, наприклад, сервіс Grafana називається `prometheus-grafana`.

## 4. Доступ до Grafana

1. Створіть DNS-запис для `grafana.<DOMAIN_BASE>`, що вказує на `<SERVER_IP>`, або для налаштування лише в LAN додайте до `/etc/hosts` на клієнтській машині:
   ```
   <SERVER_IP>   grafana.<DOMAIN_BASE>
   ```
2. Відкрийте `https://grafana.<DOMAIN_BASE>`. Попередження браузера про самопідписаний сертифікат Traefik очікуване, якщо ви не налаштували справжній сертифікат.
3. Увійдіть як `admin` з паролем `<GRAFANA_ADMIN_PASSWORD>`.

Немає DNS? Використовуйте port-forward замість ingress:

```bash
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
# http://localhost:3000
```

Відновлення забутого пароля:

```bash
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

> **Попередження:** після першого запуску пароль зберігається в базі даних Grafana. Подальша зміна Secret його не змінює; скористайтеся `kubectl -n monitoring exec deploy/prometheus-grafana -c grafana -- grafana cli admin reset-admin-password '<NEW_PASSWORD>'`.

## 5. Дашборди

Chart постачається з готовими дашбордами (меню Dashboards):

| Дашборд | Що показує |
|---|---|
| Kubernetes / Compute Resources / Cluster | CPU і RAM усього кластера |
| Kubernetes / Compute Resources / Namespace (Pods) | Споживання по namespace; порівняйте namespace'и проєктів з `monitoring` |
| Kubernetes / Compute Resources / Pod | Один pod, по контейнерах |
| Node Exporter / Nodes | CPU, пам'ять, диск, мережа хоста |

Додаткові дашборди спільноти: Dashboards > New > Import, введіть ID, оберіть джерело даних `Prometheus`.

| ID | Назва |
|---|---|
| 1860 | Node Exporter Full |
| 15757 | Kubernetes / Views / Global |
| 15760 | Kubernetes / Views / Pods |

## 6. Ключові запити PromQL

Виконуйте їх в Explore з джерелом даних `Prometheus`.

| Мета | Запит |
|---|---|
| Використання CPU вузла, % | `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| Використання RAM вузла, % | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` |
| Використання кореневого диска, % | `(1 - node_filesystem_avail_bytes{mountpoint="/",fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="tmpfs"}) * 100` |
| Пам'ять pod'ів за namespace | `sum by (namespace) (container_memory_working_set_bytes{container!=""})` |
| CPU pod'ів (ядра) у namespace | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="<PROJECT_NAME>",container!=""}[5m]))` |
| Pod'и, що не працюють | `sum by (namespace, phase) (kube_pod_status_phase{phase=~"Pending\|Failed\|Unknown"} == 1)` |
| Перезапуски контейнерів за 1 год | `increase(kube_pod_container_status_restarts_total[1h]) > 0` |
| Недоступні цілі збору метрик | `up == 0` |

## 7. Оновлення та видалення

```bash
helm repo update
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

```bash
helm uninstall prometheus -n monitoring
kubectl -n monitoring delete pvc -l app.kubernetes.io/name=grafana   # необов'язково: видаляє дашборди
kubectl -n monitoring delete pvc -l operator.prometheus.io/name=prometheus-kube-prometheus-prometheus   # необов'язково: видаляє метрики
```

> **Попередження:** оновлення chart'а на нову мажорну версію може потребувати оновлення CRD, яке Helm не застосовує автоматично; перед переходом на нову мажорну версію дотримуйтесь приміток chart'а щодо оновлення.

## Перевірка

```bash
kubectl get pods -n monitoring        # усі Running, лічильники готовності збігаються (наприклад, 2/2)
kubectl get pvc -n monitoring         # усі Bound
kubectl get ingress -n monitoring     # хост grafana.<DOMAIN_BASE>
```

У Grafana: Explore > `Prometheus` > запит `up` повертає серії зі значенням `1`. Графіки залишаються порожніми перші 2-3 хвилини після встановлення.

| Симптом | Виправлення |
|---|---|
| PVC `Pending` | Немає типового StorageClass; `kubectl get storageclass` має показувати `local-path` |
| Pod `OOMKilled` / `CrashLoopBackOff` | `kubectl describe pod -n monitoring <POD>`; збільште ліміт пам'яті або зменште `retention` |
| 404 від Traefik | Хост Ingress відрізняється від використаної URL-адреси; перевірте `kubectl get ingress -n monitoring` |

Далі: [Журнали Loki](loki-logs.md)
