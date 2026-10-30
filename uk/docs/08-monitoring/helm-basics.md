# Основи Helm

Встановлює Helm, менеджер пакетів для Kubernetes, і налаштовує namespace `monitoring` та каталог для values-файлів, що використовуються в наступних документах.

Helm пакує багато YAML-маніфестів в один **chart**. **Release** — це один встановлений екземпляр chart'а. **Values-файл** перевизначає типові значення chart'а без його редагування.

## 1. Встановлення Helm

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh
helm version
```

## 2. Підключення Helm до кластера K3s

Helm використовує той самий kubeconfig, що й `kubectl`. K3s записує його в `/etc/rancher/k3s/k3s.yaml` (доступний лише root). Скопіюйте його один раз для `<SERVER_USER>`:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown <SERVER_USER>:<SERVER_USER> ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config
```

> **Попередження:** без цього Helm завершується помилкою `Kubernetes cluster unreachable: ... localhost:8080` або `permission denied` на `k3s.yaml`.

Про сам кластер див. [встановлення K3s](../03-containers-and-k3s/k3s-install.md).

## 3. Namespace та репозиторії

```bash
kubectl create namespace monitoring

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

| Репозиторій | Використовувані chart'и |
|---|---|
| `prometheus-community` | `kube-prometheus-stack` |
| `grafana` | `loki`, `promtail` |

## 4. Де зберігати values-файли

```bash
mkdir -p ~/k8s-infrastructure/system/monitoring
```

Один values-файл на release, поруч з іншими маніфестами кластера (див. [угоди щодо структури Kubernetes](../05-deploying-projects/k8s-structure-conventions.md)):

```
~/k8s-infrastructure/system/monitoring/
├── kube-prometheus-stack-values.yaml
├── loki-values.yaml
└── promtail-values.yaml
```

> **Попередження:** ніколи не комітьте паролі у values-файли. У наступному документі пароль Grafana зберігається в Kubernetes Secret.

## 5. Довідник команд

| Завдання | Команда |
|---|---|
| Пошук chart'а | `helm search repo loki` |
| Показати типові значення | `helm show values grafana/loki > /tmp/loki-defaults.yaml` |
| Встановити | `helm install <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml --wait --timeout 10m` |
| Оновити (застосувати змінені значення) | `helm upgrade <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml --wait` |
| Встановити або оновити | `helm upgrade --install <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml` |
| Список release'ів | `helm list -n monitoring` |
| Значення release'у, що використовуються | `helm get values <RELEASE> -n monitoring` |
| Історія / відкат | `helm history <RELEASE> -n monitoring` / `helm rollback <RELEASE> <REVISION> -n monitoring` |
| Видалити | `helm uninstall <RELEASE> -n monitoring` |
| Згенерувати без встановлення | `helm template <RELEASE> <REPO>/<CHART> -f values.yaml` |

- `--wait --timeout 10m` блокує виконання, доки всі pod'и не будуть готові; під час першого встановлення завантажується кілька образів, це може тривати хвилини.
- `helm upgrade` заново читає весь values-файл. Щоразу передавайте файл повністю; пропущені ключі повертаються до типових значень chart'а.
- Фіксуйте версії для відтворюваності: `--version <CHART_VERSION>` (див. `helm search repo <CHART> --versions`).
- `cannot re-use a name that is still in use` означає, що release уже існує; використовуйте `upgrade`.
- `helm uninstall` не видаляє PersistentVolumeClaim'и, створені StatefulSet'ами; видаліть їх явно, якщо дані більше не потрібні.

## Перевірка

```bash
helm version --short
kubectl get ns monitoring
helm repo list
```

Далі: [Prometheus і Grafana](prometheus-grafana.md)
