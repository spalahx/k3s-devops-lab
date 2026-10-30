# Helm Basics

Installs Helm, the package manager for Kubernetes, and sets up the `monitoring` namespace and the directory for values files used by the next documents.

Helm packages many YAML manifests into one **chart**. A **release** is one installed instance of a chart. A **values file** overrides the chart defaults without editing the chart.

## 1. Install Helm

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh
helm version
```

## 2. Point Helm at the K3s cluster

Helm uses the same kubeconfig as `kubectl`. K3s writes it to `/etc/rancher/k3s/k3s.yaml` (root-only). Copy it once for `<SERVER_USER>`:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown <SERVER_USER>:<SERVER_USER> ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config
```

> **Warning:** Without this, Helm fails with `Kubernetes cluster unreachable: ... localhost:8080` or `permission denied` on `k3s.yaml`.

See [K3s install](../03-containers-and-k3s/k3s-install.md) for the cluster itself.

## 3. Namespace and repositories

```bash
kubectl create namespace monitoring

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

| Repo | Charts used |
|---|---|
| `prometheus-community` | `kube-prometheus-stack` |
| `grafana` | `loki`, `promtail` |

## 4. Where to store values files

```bash
mkdir -p ~/k8s-infrastructure/system/monitoring
```

One values file per release, kept next to the other cluster manifests (see [Kubernetes structure conventions](../05-deploying-projects/k8s-structure-conventions.md)):

```
~/k8s-infrastructure/system/monitoring/
├── kube-prometheus-stack-values.yaml
├── loki-values.yaml
└── promtail-values.yaml
```

> **Warning:** Never commit passwords in values files. The next document keeps the Grafana password in a Kubernetes Secret instead.

## 5. Command reference

| Task | Command |
|---|---|
| Search a chart | `helm search repo loki` |
| Show default values | `helm show values grafana/loki > /tmp/loki-defaults.yaml` |
| Install | `helm install <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml --wait --timeout 10m` |
| Upgrade (apply changed values) | `helm upgrade <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml --wait` |
| Install or upgrade | `helm upgrade --install <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml` |
| List releases | `helm list -n monitoring` |
| Release values in use | `helm get values <RELEASE> -n monitoring` |
| History / rollback | `helm history <RELEASE> -n monitoring` / `helm rollback <RELEASE> <REVISION> -n monitoring` |
| Uninstall | `helm uninstall <RELEASE> -n monitoring` |
| Render without installing | `helm template <RELEASE> <REPO>/<CHART> -f values.yaml` |

- `--wait --timeout 10m` blocks until all pods are ready; the first install pulls several images and can take minutes.
- `helm upgrade` re-reads the whole values file. Pass the full file every time; omitted keys revert to chart defaults.
- Pin versions for reproducibility: `--version <CHART_VERSION>` (see `helm search repo <CHART> --versions`).
- `cannot re-use a name that is still in use` means the release exists; use `upgrade`.
- `helm uninstall` does not delete PersistentVolumeClaims created by StatefulSets; delete them explicitly if the data is no longer needed.

## Verify

```bash
helm version --short
kubectl get ns monitoring
helm repo list
```

Next: [Prometheus and Grafana](prometheus-grafana.md)
