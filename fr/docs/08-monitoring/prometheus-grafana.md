# Prometheus et Grafana

Installe `kube-prometheus-stack` (Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics) dans le namespace `monitoring`, ajusté pour un petit serveur K3s mono-nœud, avec Grafana exposé via Traefik à l'adresse `grafana.<DOMAIN_BASE>`.

| Composant | Rôle |
|---|---|
| Prometheus | Collecte et stocke les métriques (valeurs numériques dans le temps) |
| Alertmanager | Achemine les alertes déclenchées par les règles de Prometheus |
| node-exporter | Métriques de l'hôte : CPU, RAM, disque, réseau (un pod par nœud) |
| kube-state-metrics | État des objets Kubernetes : phases des pods, redémarrages, déploiements |
| Grafana | Tableaux de bord sur Prometheus (et Loki, voir le document suivant) |

Prérequis : [Bases de Helm](helm-basics.md) terminées ; `kubectl get storageclass` liste `local-path` (fourni avec K3s ; les données se trouvent sous `/var/lib/rancher/k3s/storage/` et survivent aux redémarrages) ; au moins 2 Go de RAM libre (`free -h`, colonne `available`).

## 1. Mot de passe administrateur de Grafana

`<GRAFANA_ADMIN_PASSWORD>` est un mot de passe que vous choisissez pour l'utilisateur `admin` de Grafana. Stockez-le dans un Secret pour qu'il n'atterrisse jamais dans Git :

```bash
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<GRAFANA_ADMIN_PASSWORD>'
```

## 2. Fichier de valeurs

`~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml` :

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
  # La source de données Loki est ajoutée dans le document suivant

# K3s exécute ces composants dans un seul processus et n'expose pas leurs métriques ;
# les laisser activés produit en permanence des alertes « target down ».
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

| Clé | Raison |
|---|---|
| `retention` + `retentionSize` | Prometheus supprime les données plus anciennes que la limite de temps ou au-delà de la limite de taille, selon la première atteinte ; gardez `retentionSize` sous la taille du PVC (environ 80 %) |
| `storageClassName: local-path` | Sans PVC, les métriques sont perdues à chaque redémarrage du pod |
| limites `memory` | Plafonnent la RAM pour qu'un pic de cardinalité ne prive pas de ressources les projets du même nœud |
| `grafana.ingress.hosts` | Doit être identique au nom d'hôte que vous ouvrez dans le navigateur, sinon Traefik renvoie 404 |
| `kube*: enabled: false` | Spécifique à K3s, voir le commentaire dans le fichier |

## 3. Installation

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

Le nom de release `prometheus` préfixe tous les objets ; par exemple, le service Grafana est `prometheus-grafana`.

## 4. Accéder à Grafana

1. Créez un enregistrement DNS pour `grafana.<DOMAIN_BASE>` pointant vers `<SERVER_IP>` ou, pour une configuration LAN uniquement, ajoutez à `/etc/hosts` sur la machine cliente :
   ```
   <SERVER_IP>   grafana.<DOMAIN_BASE>
   ```
2. Ouvrez `https://grafana.<DOMAIN_BASE>`. Un avertissement du navigateur concernant le certificat auto-signé de Traefik est normal, sauf si vous avez configuré un vrai certificat.
3. Connectez-vous en tant que `admin` avec `<GRAFANA_ADMIN_PASSWORD>`.

Pas de DNS disponible ? Utilisez un port-forward au lieu de l'ingress :

```bash
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
# http://localhost:3000
```

Récupérer un mot de passe oublié :

```bash
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

> **Avertissement :** après le premier démarrage, le mot de passe est stocké dans la base de données de Grafana. Modifier le Secret par la suite ne le change pas ; utilisez `kubectl -n monitoring exec deploy/prometheus-grafana -c grafana -- grafana cli admin reset-admin-password '<NEW_PASSWORD>'`.

## 5. Tableaux de bord

Le chart fournit des tableaux de bord prêts à l'emploi (menu Dashboards) :

| Tableau de bord | Affiche |
|---|---|
| Kubernetes / Compute Resources / Cluster | CPU et RAM de l'ensemble du cluster |
| Kubernetes / Compute Resources / Namespace (Pods) | Consommation par namespace ; comparez les namespaces des projets avec `monitoring` |
| Kubernetes / Compute Resources / Pod | Un pod, par conteneur |
| Node Exporter / Nodes | CPU, mémoire, disque et réseau de l'hôte |

Tableaux de bord communautaires supplémentaires : Dashboards > New > Import, saisissez l'ID, choisissez la source de données `Prometheus`.

| ID | Nom |
|---|---|
| 1860 | Node Exporter Full |
| 15757 | Kubernetes / Views / Global |
| 15760 | Kubernetes / Views / Pods |

## 6. Requêtes PromQL clés

Exécutez-les dans Explore avec la source de données `Prometheus`.

| Objectif | Requête |
|---|---|
| Utilisation CPU du nœud, % | `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| Utilisation RAM du nœud, % | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` |
| Utilisation du disque racine, % | `(1 - node_filesystem_avail_bytes{mountpoint="/",fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="tmpfs"}) * 100` |
| Mémoire des pods par namespace | `sum by (namespace) (container_memory_working_set_bytes{container!=""})` |
| CPU des pods (cœurs) dans un namespace | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="<PROJECT_NAME>",container!=""}[5m]))` |
| Pods qui ne sont pas en cours d'exécution | `sum by (namespace, phase) (kube_pod_status_phase{phase=~"Pending\|Failed\|Unknown"} == 1)` |
| Redémarrages de conteneurs, 1 h | `increase(kube_pod_container_status_restarts_total[1h]) > 0` |
| Cibles de collecte hors service | `up == 0` |

## 7. Mise à jour et désinstallation

```bash
helm repo update
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

```bash
helm uninstall prometheus -n monitoring
kubectl -n monitoring delete pvc -l app.kubernetes.io/name=grafana   # optionnel : supprime les tableaux de bord
kubectl -n monitoring delete pvc -l operator.prometheus.io/name=prometheus-kube-prometheus-prometheus   # optionnel : supprime les métriques
```

> **Avertissement :** les mises à jour majeures du chart peuvent nécessiter des mises à jour des CRD, que Helm n'applique pas automatiquement ; suivez les notes de mise à jour du chart avant un saut de version majeure.

## Vérification

```bash
kubectl get pods -n monitoring        # all Running, ready counts match (e.g. 2/2)
kubectl get pvc -n monitoring         # all Bound
kubectl get ingress -n monitoring     # host grafana.<DOMAIN_BASE>
```

Dans Grafana : Explore > `Prometheus` > la requête `up` renvoie des séries avec la valeur `1`. Les graphiques restent vides pendant les 2 à 3 premières minutes après l'installation.

| Symptôme | Solution |
|---|---|
| PVC en `Pending` | Aucune StorageClass par défaut ; `kubectl get storageclass` doit afficher `local-path` |
| Pod `OOMKilled` / `CrashLoopBackOff` | `kubectl describe pod -n monitoring <POD>` ; augmentez la limite de mémoire ou réduisez `retention` |
| 404 de Traefik | L'hôte de l'Ingress diffère de l'URL utilisée ; vérifiez `kubectl get ingress -n monitoring` |

Suite : [Journaux Loki](loki-logs.md)
