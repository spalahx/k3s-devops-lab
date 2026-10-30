# Bases de Helm

Installe Helm, le gestionnaire de paquets pour Kubernetes, et prépare le namespace `monitoring` ainsi que le répertoire des fichiers de valeurs utilisés par les documents suivants.

Helm regroupe de nombreux manifestes YAML en un seul **chart**. Une **release** est une instance installée d'un chart. Un **fichier de valeurs** remplace les valeurs par défaut du chart sans modifier celui-ci.

## 1. Installer Helm

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh
helm version
```

## 2. Pointer Helm vers le cluster K3s

Helm utilise le même kubeconfig que `kubectl`. K3s l'écrit dans `/etc/rancher/k3s/k3s.yaml` (accessible uniquement à root). Copiez-le une fois pour `<SERVER_USER>` :

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown <SERVER_USER>:<SERVER_USER> ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config
```

> **Avertissement :** sans cela, Helm échoue avec `Kubernetes cluster unreachable: ... localhost:8080` ou `permission denied` sur `k3s.yaml`.

Voir [Installation de K3s](../03-containers-and-k3s/k3s-install.md) pour le cluster lui-même.

## 3. Namespace et dépôts

```bash
kubectl create namespace monitoring

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

| Dépôt | Charts utilisés |
|---|---|
| `prometheus-community` | `kube-prometheus-stack` |
| `grafana` | `loki`, `promtail` |

## 4. Où stocker les fichiers de valeurs

```bash
mkdir -p ~/k8s-infrastructure/system/monitoring
```

Un fichier de valeurs par release, conservé à côté des autres manifestes du cluster (voir [Conventions de structure Kubernetes](../05-deploying-projects/k8s-structure-conventions.md)) :

```
~/k8s-infrastructure/system/monitoring/
├── kube-prometheus-stack-values.yaml
├── loki-values.yaml
└── promtail-values.yaml
```

> **Avertissement :** ne commitez jamais de mots de passe dans les fichiers de valeurs. Le document suivant conserve plutôt le mot de passe de Grafana dans un Secret Kubernetes.

## 5. Référence des commandes

| Tâche | Commande |
|---|---|
| Rechercher un chart | `helm search repo loki` |
| Afficher les valeurs par défaut | `helm show values grafana/loki > /tmp/loki-defaults.yaml` |
| Installer | `helm install <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml --wait --timeout 10m` |
| Mettre à jour (appliquer les valeurs modifiées) | `helm upgrade <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml --wait` |
| Installer ou mettre à jour | `helm upgrade --install <RELEASE> <REPO>/<CHART> -n monitoring -f values.yaml` |
| Lister les releases | `helm list -n monitoring` |
| Valeurs de la release en cours | `helm get values <RELEASE> -n monitoring` |
| Historique / retour arrière | `helm history <RELEASE> -n monitoring` / `helm rollback <RELEASE> <REVISION> -n monitoring` |
| Désinstaller | `helm uninstall <RELEASE> -n monitoring` |
| Générer sans installer | `helm template <RELEASE> <REPO>/<CHART> -f values.yaml` |

- `--wait --timeout 10m` bloque jusqu'à ce que tous les pods soient prêts ; la première installation télécharge plusieurs images et peut prendre plusieurs minutes.
- `helm upgrade` relit l'intégralité du fichier de valeurs. Passez le fichier complet à chaque fois ; les clés omises reviennent aux valeurs par défaut du chart.
- Épinglez les versions pour la reproductibilité : `--version <CHART_VERSION>` (voir `helm search repo <CHART> --versions`).
- `cannot re-use a name that is still in use` signifie que la release existe déjà ; utilisez `upgrade`.
- `helm uninstall` ne supprime pas les PersistentVolumeClaims créés par les StatefulSets ; supprimez-les explicitement si les données ne sont plus nécessaires.

## Vérification

```bash
helm version --short
kubectl get ns monitoring
helm repo list
```

Suite : [Prometheus et Grafana](prometheus-grafana.md)
