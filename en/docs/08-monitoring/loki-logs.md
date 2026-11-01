# Loki Logs

Installs Loki (log storage) in single-binary mode and Promtail (log shipper) in the `monitoring` namespace, and adds Loki as a Grafana data source.

Loki indexes only labels (`namespace`, `pod`, `container`, `app`), not log text, which keeps RAM and disk use low. Promtail runs as a DaemonSet (one pod per node), reads container log files and pushes them to Loki.

Prerequisite: [Prometheus and Grafana](prometheus-grafana.md) installed.

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

# Disable everything the distributed mode needs
gateway:      { enabled: false }
backend:      { replicas: 0 }
read:         { replicas: 0 }
write:        { replicas: 0 }
chunksCache:  { enabled: false }
resultsCache: { enabled: false }
lokiCanary:   { enabled: false }
test:         { enabled: false }
```

| Key | Why |
|---|---|
| `deploymentMode: SingleBinary` | All Loki components in one pod; enough for one node |
| `auth_enabled: false` | No multi-tenancy; Loki is reachable only inside the cluster |
| `storage.type: filesystem` | Chunks go to the PVC, no S3 needed |
| `retention_period: 168h` + `compactor.retention_enabled` | Deletes logs older than 7 days; the limit alone does nothing without the compactor flag |
| `chunksCache`, `resultsCache`, `lokiCanary`, `test` off | Saves hundreds of MB of RAM on a small server |

```bash
helm install loki grafana/loki \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/loki-values.yaml \
  --wait --timeout 5m
```

> **Warning:** If the chart version you install rejects a key above, compare with `helm show values grafana/loki`; this file was written for the 6.x chart line. The reference server runs chart 7.3.0 (Loki 3.6.12) with the same `SingleBinary` layout; still compare the keys with `helm show values grafana/loki` before installing.

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

`loki.monitoring.svc.cluster.local` is the in-cluster DNS name of the `loki` service in the `monitoring` namespace.

```bash
helm install promtail grafana/promtail \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/promtail-values.yaml \
  --wait
```

K3s uses containerd, whose logs are in the CRI format under `/var/log/pods/<namespace>_<pod>_<uid>/<container>/*.log`. The chart's default scrape config mounts `/var/log/pods` and parses the CRI format, so no path changes are needed. Adjust the mounts only if K3s runs with a custom `--data-dir` or log directory.

> **Warning:** Promtail is deprecated in favour of Grafana Alloy; check the project's status page before relying on it for a new installation. The reference server runs Loki without any log shipper, so the Promtail steps on this page were not verified on real hardware. Prefer Alloy for a new setup.

## 3. Add Loki to Grafana

Add under `grafana:` in `kube-prometheus-stack-values.yaml`:

```yaml
grafana:
  # ...existing keys...
  additionalDataSources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki.monitoring.svc.cluster.local:3100
```

Apply:

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

Quick alternative without Helm: Grafana > Connections > Data sources > Add > Loki, URL `http://loki.monitoring.svc.cluster.local:3100`, Save & test. It persists on the Grafana PVC but is lost on a fresh reinstall.

Optional logs dashboard: Dashboards > New > Import, ID `13639`, data source `Loki`.

## 4. LogQL examples

Grafana > Explore > data source `Loki`. A query always starts with a label selector; filters after it are optional.

| Query | Result |
|---|---|
| `{namespace="<PROJECT_NAME>"}` | All logs of a namespace |
| `{namespace="<PROJECT_NAME>", pod=~"app-.*"}` | Pods whose name matches a regex |
| `{namespace="<PROJECT_NAME>", container="mysql"}` | One container |
| `{namespace="<PROJECT_NAME>"} \|= "error"` | Lines containing `error` |
| `{namespace="<PROJECT_NAME>"} \|~ "(?i)fatal\|exception"` | Case-insensitive regex |
| `{namespace="<PROJECT_NAME>"} != "healthcheck"` | Lines without `healthcheck` |
| `{namespace="monitoring"}` | Logs of the monitoring stack itself |
| `sum by (pod) (rate({namespace="<PROJECT_NAME>"} \|= "error" [5m]))` | Error rate per pod |
| `sum by (namespace) (count_over_time({namespace=~".+"}[1h]))` | Log volume per namespace |

Operators: `\|=` contains, `!=` does not contain, `\|~` regex match, `!~` regex not match. (In Markdown tables the pipe is escaped as `\|`; type a plain `|` in Grafana.)

## Retention and disk

- Logs are deleted after `retention_period` (7 days above) by the compactor, which runs about every 10 minutes.
- PVC size (10Gi) must cover `retention_period` multiplied by daily log volume; check usage:
  ```bash
  kubectl -n monitoring exec loki-0 -c loki -- df -h /var/loki
  ```
- Verbose applications (debug logging, access logs) dominate volume; exclude noise with `!=` in queries and fix it at the source.

## Verify

```bash
helm list -n monitoring                                   # loki, prometheus, promtail: deployed
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki       # Running, 2/2 (sidecar included)
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail   # one per node, Running
kubectl get pvc -n monitoring                             # all Bound
```

Grafana > Connections > Data sources > Loki > Save & test shows a green message. Query `{namespace="monitoring"}` in Explore returns lines.

## Troubleshooting empty logs

| Check | Command / action |
|---|---|
| Promtail running | `kubectl -n monitoring get pods -l app.kubernetes.io/name=promtail` |
| Promtail errors (connection refused, 429, 400) | `kubectl -n monitoring logs ds/promtail --tail=50` |
| Loki reachable from the cluster | `kubectl -n monitoring run curl --rm -it --image=curlimages/curl --restart=Never -- curl -s http://loki:3100/ready` should print `ready` (may take about 15 s after start) |
| Labels exist | Explore > Label browser; use only listed `namespace` values |
| Time range | Set Explore to "Last 15 minutes"; the first lines appear within a minute |
| Files visible to Promtail | `kubectl -n monitoring exec ds/promtail -- ls /var/log/pods` should list pod directories |
| Loki rejects old lines | `reject_old_samples` drops entries older than a week; irrelevant for fresh logs |
| Loki `CrashLoopBackOff` | `kubectl -n monitoring logs loki-0 -c loki`; usually a YAML/schema error in values or too low memory limit |
| Data source test fails | URL must be exactly `http://loki.monitoring.svc.cluster.local:3100`, no trailing path |

Next: [Glossary](../99-appendix/glossary.md)
