# Journaux Loki

Installe Loki (stockage des journaux) en mode single-binary et Promtail (collecteur de journaux) dans le namespace `monitoring`, puis ajoute Loki comme source de données Grafana.

Loki n'indexe que les étiquettes (`namespace`, `pod`, `container`, `app`), pas le texte des journaux, ce qui limite l'utilisation de la RAM et du disque. Promtail s'exécute en DaemonSet (un pod par nœud), lit les fichiers de journaux des conteneurs et les envoie à Loki.

Prérequis : [Prometheus et Grafana](prometheus-grafana.md) installés.

## 1. Loki

`~/k8s-infrastructure/system/monitoring/loki-values.yaml` :

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

# Désactive tout ce dont le mode distribué a besoin
gateway:      { enabled: false }
backend:      { replicas: 0 }
read:         { replicas: 0 }
write:        { replicas: 0 }
chunksCache:  { enabled: false }
resultsCache: { enabled: false }
lokiCanary:   { enabled: false }
test:         { enabled: false }
```

| Clé | Raison |
|---|---|
| `deploymentMode: SingleBinary` | Tous les composants de Loki dans un seul pod ; suffisant pour un nœud |
| `auth_enabled: false` | Pas de multi-tenance ; Loki n'est accessible qu'à l'intérieur du cluster |
| `storage.type: filesystem` | Les chunks vont sur le PVC, pas besoin de S3 |
| `retention_period: 168h` + `compactor.retention_enabled` | Supprime les journaux de plus de 7 jours ; la limite seule ne fait rien sans l'option du compactor |
| `chunksCache`, `resultsCache`, `lokiCanary`, `test` désactivés | Économise des centaines de Mo de RAM sur un petit serveur |

```bash
helm install loki grafana/loki \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/loki-values.yaml \
  --wait --timeout 5m
```

> **Avertissement :** si la version du chart que vous installez rejette une clé ci-dessus, comparez avec `helm show values grafana/loki` ; ce fichier a été écrit pour la branche 6.x du chart. Le serveur de référence utilise le chart 7.3.0 (Loki 3.6.12) avec la même disposition `SingleBinary` ; comparez quand même les clés avec `helm show values grafana/loki` avant l'installation.

## 2. Promtail

`~/k8s-infrastructure/system/monitoring/promtail-values.yaml` :

```yaml
config:
  clients:
    - url: http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push

resources:
  requests: { cpu: 25m, memory: 64Mi }
  limits:   { memory: 128Mi }
```

`loki.monitoring.svc.cluster.local` est le nom DNS interne au cluster du service `loki` dans le namespace `monitoring`.

```bash
helm install promtail grafana/promtail \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/promtail-values.yaml \
  --wait
```

K3s utilise containerd, dont les journaux sont au format CRI sous `/var/log/pods/<namespace>_<pod>_<uid>/<container>/*.log`. La configuration de collecte par défaut du chart monte `/var/log/pods` et analyse le format CRI, aucun changement de chemin n'est donc nécessaire. N'ajustez les montages que si K3s s'exécute avec un `--data-dir` ou un répertoire de journaux personnalisé.

> **Avertissement :** Promtail est déprécié au profit de Grafana Alloy ; vérifiez l'état du projet avant de l'utiliser pour une nouvelle installation. Le serveur de référence exécute Loki sans aucun collecteur de logs : les étapes Promtail de cette page n'ont donc pas été vérifiées sur du matériel réel. Préférez Alloy pour une nouvelle installation.

## 3. Ajouter Loki à Grafana

Ajoutez sous `grafana:` dans `kube-prometheus-stack-values.yaml` :

```yaml
grafana:
  # ...clés existantes...
  additionalDataSources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki.monitoring.svc.cluster.local:3100
```

Appliquez :

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/k8s-infrastructure/system/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

Alternative rapide sans Helm : Grafana > Connections > Data sources > Add > Loki, URL `http://loki.monitoring.svc.cluster.local:3100`, Save & test. Elle est conservée sur le PVC de Grafana mais perdue lors d'une réinstallation complète.

Tableau de bord de journaux optionnel : Dashboards > New > Import, ID `13639`, source de données `Loki`.

## 4. Exemples LogQL

Grafana > Explore > source de données `Loki`. Une requête commence toujours par un sélecteur d'étiquettes ; les filtres qui suivent sont facultatifs.

| Requête | Résultat |
|---|---|
| `{namespace="<PROJECT_NAME>"}` | Tous les journaux d'un namespace |
| `{namespace="<PROJECT_NAME>", pod=~"app-.*"}` | Pods dont le nom correspond à une expression régulière |
| `{namespace="<PROJECT_NAME>", container="mysql"}` | Un conteneur |
| `{namespace="<PROJECT_NAME>"} \|= "error"` | Lignes contenant `error` |
| `{namespace="<PROJECT_NAME>"} \|~ "(?i)fatal\|exception"` | Expression régulière insensible à la casse |
| `{namespace="<PROJECT_NAME>"} != "healthcheck"` | Lignes sans `healthcheck` |
| `{namespace="monitoring"}` | Journaux de la pile de supervision elle-même |
| `sum by (pod) (rate({namespace="<PROJECT_NAME>"} \|= "error" [5m]))` | Taux d'erreurs par pod |
| `sum by (namespace) (count_over_time({namespace=~".+"}[1h]))` | Volume de journaux par namespace |

Opérateurs : `\|=` contient, `!=` ne contient pas, `\|~` correspond à l'expression régulière, `!~` ne correspond pas à l'expression régulière. (Dans les tableaux Markdown, la barre verticale est échappée en `\|` ; saisissez un simple `|` dans Grafana.)

## Rétention et disque

- Les journaux sont supprimés après `retention_period` (7 jours ci-dessus) par le compactor, qui s'exécute environ toutes les 10 minutes.
- La taille du PVC (10Gi) doit couvrir `retention_period` multiplié par le volume quotidien de journaux ; vérifiez l'utilisation :
  ```bash
  kubectl -n monitoring exec loki-0 -c loki -- df -h /var/loki
  ```
- Les applications verbeuses (journalisation debug, journaux d'accès) dominent le volume ; excluez le bruit avec `!=` dans les requêtes et corrigez-le à la source.

## Vérification

```bash
helm list -n monitoring                                   # loki, prometheus, promtail: deployed
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki       # Running, 2/2 (sidecar included)
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail   # one per node, Running
kubectl get pvc -n monitoring                             # all Bound
```

Grafana > Connections > Data sources > Loki > Save & test affiche un message vert. La requête `{namespace="monitoring"}` dans Explore renvoie des lignes.

## Dépannage : journaux vides

| Vérification | Commande / action |
|---|---|
| Promtail en cours d'exécution | `kubectl -n monitoring get pods -l app.kubernetes.io/name=promtail` |
| Erreurs de Promtail (connection refused, 429, 400) | `kubectl -n monitoring logs ds/promtail --tail=50` |
| Loki accessible depuis le cluster | `kubectl -n monitoring run curl --rm -it --image=curlimages/curl --restart=Never -- curl -s http://loki:3100/ready` doit afficher `ready` (peut prendre environ 15 s après le démarrage) |
| Les étiquettes existent | Explore > Label browser ; n'utilisez que les valeurs de `namespace` listées |
| Plage de temps | Réglez Explore sur « Last 15 minutes » ; les premières lignes apparaissent en moins d'une minute |
| Fichiers visibles par Promtail | `kubectl -n monitoring exec ds/promtail -- ls /var/log/pods` doit lister les répertoires des pods |
| Loki rejette les anciennes lignes | `reject_old_samples` écarte les entrées de plus d'une semaine ; sans importance pour des journaux récents |
| Loki en `CrashLoopBackOff` | `kubectl -n monitoring logs loki-0 -c loki` ; généralement une erreur YAML/schéma dans les valeurs ou une limite de mémoire trop basse |
| Le test de la source de données échoue | L'URL doit être exactement `http://loki.monitoring.svc.cluster.local:3100`, sans chemin final |

Suite : [Glossaire](../99-appendix/glossary.md)
