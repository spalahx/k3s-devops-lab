# Основы Helm

Устанавливает Helm, менеджер пакетов для Kubernetes, и подготавливает namespace `monitoring` и каталог для values-файлов, которые используются в следующих документах.

Helm упаковывает множество YAML-манифестов в один **chart** (пакет). **Release** (релиз) это одна установленная копия chart. **Values-файл** переопределяет значения chart по умолчанию, не меняя сам chart.

## 1. Установка Helm

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh
helm version
```

## 2. Подключение Helm к кластеру K3s

Helm использует тот же kubeconfig, что и `kubectl`. K3s записывает его в `/etc/rancher/k3s/k3s.yaml` (доступен только root). Один раз скопируйте его для `<SERVER_USER>`:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown <SERVER_USER>:<SERVER_USER> ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config
```

> **Warning:** Без этого Helm падает с `Kubernetes cluster unreachable: ... localhost:8080` или `permission denied` на `k3s.yaml`.

Установка самого кластера: [установка K3s](../03-containers-and-k3s/k3s-install.md).

## 3. Namespace и репозитории

```bash
kubectl create namespace monitoring

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

| Репозиторий | Используемые chart |
|---|---|
| `prometheus-community` | `kube-prometheus-stack` |
| `grafana` | `loki`, `promtail` |

## 4. Где хранить values-файлы

```bash
mkdir -p ~/k8s-infrastructure/system/monitoring
```

Один values-файл на релиз, рядом с остальными манифестами кластера (см. [соглашения по структуре Kubernetes](../05-deploying-projects/k8s-structure-conventions.md)):

```
~/k8s-infrastructure/system/monitoring/
├── kube-prometheus-stack-values.yaml
├── loki-values.yaml
└── promtail-values.yaml
```

> **Warning:** Не коммитьте пароли в values-файлы. В следующем документе пароль Grafana хранится в Kubernetes Secret.

## 5. Справочник команд

| Задача | Команда |
|---|---|
| Поиск chart | `helm search repo loki` |
| Значения по умолчанию | `helm show values grafana/loki > /tmp/loki-defaults.yaml` |
| Установка | `helm install <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml --wait --timeout 10m` |
| Обновление (применить изменённые values) | `helm upgrade <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml --wait` |
| Установка или обновление | `helm upgrade --install <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml` |
| Список релизов | `helm list -n monitoring` |
| Применённые values релиза | `helm get values <RELEASE> -n monitoring` |
| История / откат | `helm history <RELEASE> -n monitoring` / `helm rollback <RELEASE> <REVISION> -n monitoring` |
| Удаление | `helm uninstall <RELEASE> -n monitoring` |
| Рендер без установки | `helm template <RELEASE> <REPO>/<CHART> -f values.yaml` |

- `--wait --timeout 10m` блокирует терминал, пока все поды не станут готовы; первая установка скачивает несколько образов и может идти несколько минут.
- `helm upgrade` перечитывает весь values-файл. Передавайте файл целиком каждый раз; пропущенные ключи возвращаются к значениям chart по умолчанию.
- Для воспроизводимости фиксируйте версию: `--version <CHART_VERSION>` (список: `helm search repo <CHART> --versions`).
- `cannot re-use a name that is still in use` означает, что релиз уже существует; используйте `upgrade`.
- `helm uninstall` не удаляет PersistentVolumeClaim, созданные StatefulSet; удалите их вручную, если данные не нужны.

## Verify

```bash
helm version --short
kubectl get ns monitoring
helm repo list
```

Next: [Prometheus и Grafana](prometheus-grafana.md)
