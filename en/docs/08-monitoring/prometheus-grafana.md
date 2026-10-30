# Prometheus and Grafana

Installs `kube-prometheus-stack` (Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics) in the `monitoring` namespace, tuned for a small single-node K3s server, with Grafana exposed through Traefik at `grafana.<DOMAIN_BASE>`.

| Component | Role |
|---|---|
| Prometheus | Scrapes and stores metrics (numbers over time) |
| Alertmanager | Routes alerts fired by Prometheus rules |
| node-exporter | Host metrics: CPU, RAM, disk, network (one pod per node) |
| kube-state-metrics | Kubernetes object state: pod phases, restarts, deployments |
| Grafana | Dashboards over Prometheus (and Loki, see next document) |

Prerequisites: [Helm basics](helm-basics.md) done; `kubectl get storageclass` lists `local-path` (shipped with K3s; data lives under `/var/lib/rancher/k3s/storage/` and survives reboots); at least 2 GB of free RAM (`free -h`, column `available`).

## 1. Grafana admin password

`<GRAFANA_ADMIN_PASSWORD>` is a password you choose for the Grafana `admin` user. Store it in a Secret so it never lands in Git:

```bash
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<GRAFANA_ADMIN_PASSWORD>'
```

## 2. Values file

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
  # Loki data source is added in the next document

# K3s runs these inside one process and does not expose their metrics;
# leaving them enabled produces permanent "target down" alerts.
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

| Key | Why |
|---|---|
| `retention` + `retentionSize` | Prometheus deletes data older than the time limit or beyond the size limit, whichever hits first; keep `retentionSize` below the PVC size (about 80%) |
| `storageClassName: local-path` | Without a PVC, metrics are lost on every pod restart |
| `memory` limits | Cap RAM so a cardinality spike cannot starve the projects on the same node |
| `grafana.ingress.hosts` | Must equal the hostname you open in the browser, otherwise Traefik returns 404 |
| `kube*: enabled: false` | K3s-specific, see comment in the file |

## 3. Install

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

The release name `prometheus` prefixes all objects, e.g. the Grafana service is `prometheus-grafana`.

## 4. Access Grafana

1. Create a DNS record for `grafana.<DOMAIN_BASE>` pointing at `<SERVER_IP>`, or for a LAN-only setup add to `/etc/hosts` on the client machine:
   ```
   <SERVER_IP>   grafana.<DOMAIN_BASE>
   ```
2. Open `https://grafana.<DOMAIN_BASE>`. A browser warning about the self-signed Traefik certificate is expected unless you configured a real certificate.
3. Log in as `admin` with `<GRAFANA_ADMIN_PASSWORD>`.

No DNS available? Use a port-forward instead of the ingress:

```bash
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
# http://localhost:3000
```

Recover a forgotten password:

```bash
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

> **Warning:** After the first start the password is stored in Grafana's database. Changing the Secret later does not change it; use `kubectl -n monitoring exec deploy/prometheus-grafana -c grafana -- grafana cli admin reset-admin-password '<NEW_PASSWORD>'`.

## 5. Dashboards

The chart ships ready dashboards (Dashboards menu):

| Dashboard | Shows |
|---|---|
| Kubernetes / Compute Resources / Cluster | CPU and RAM of the whole cluster |
| Kubernetes / Compute Resources / Namespace (Pods) | Per-namespace consumption; compare project namespaces with `monitoring` |
| Kubernetes / Compute Resources / Pod | One pod, per container |
| Node Exporter / Nodes | Host CPU, memory, disk, network |

Extra community dashboards: Dashboards > New > Import, enter the ID, choose the `Prometheus` data source.

| ID | Name |
|---|---|
| 1860 | Node Exporter Full |
| 15757 | Kubernetes / Views / Global |
| 15760 | Kubernetes / Views / Pods |

## 6. Key PromQL queries

Run them in Explore with the `Prometheus` data source.

| Purpose | Query |
|---|---|
| Node CPU usage, % | `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| Node RAM usage, % | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` |
| Root disk usage, % | `(1 - node_filesystem_avail_bytes{mountpoint="/",fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="tmpfs"}) * 100` |
| Pod memory by namespace | `sum by (namespace) (container_memory_working_set_bytes{container!=""})` |
| Pod CPU (cores) in a namespace | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="<PROJECT_NAME>",container!=""}[5m]))` |
| Pods not running | `sum by (namespace, phase) (kube_pod_status_phase{phase=~"Pending\|Failed\|Unknown"} == 1)` |
| Container restarts, 1 h | `increase(kube_pod_container_status_restarts_total[1h]) > 0` |
| Scrape targets down | `up == 0` |

## 7. Upgrade and uninstall

```bash
helm repo update
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

```bash
helm uninstall prometheus -n monitoring
kubectl -n monitoring delete pvc -l app.kubernetes.io/name=grafana   # optional: deletes dashboards
kubectl -n monitoring delete pvc -l operator.prometheus.io/name=prometheus-kube-prometheus-prometheus   # optional: deletes metrics
```

> **Warning:** Major chart upgrades may need CRD updates, which Helm does not apply automatically; follow the chart's upgrade notes before a major version jump.

## Verify

```bash
kubectl get pods -n monitoring        # all Running, ready counts match (e.g. 2/2)
kubectl get pvc -n monitoring         # all Bound
kubectl get ingress -n monitoring     # host grafana.<DOMAIN_BASE>
```

In Grafana: Explore > `Prometheus` > query `up` returns series with value `1`. Graphs stay empty for the first 2-3 minutes after install.

| Symptom | Fix |
|---|---|
| PVC `Pending` | No default StorageClass; `kubectl get storageclass` must show `local-path` |
| Pod `OOMKilled` / `CrashLoopBackOff` | `kubectl describe pod -n monitoring <POD>`; raise the memory limit or lower `retention` |
| 404 from Traefik | Ingress host differs from the URL used; check `kubectl get ingress -n monitoring` |

Next: [Loki logs](loki-logs.md)
