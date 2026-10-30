# Référence : manifeste de l'application (`app.yaml`)

Notes champ par champ sur [`examples/wordpress/app.yaml`](../../../examples/wordpress/app.yaml) : un Pod avec PHP-FPM et Nginx, un Service et un Ingress Traefik. À utiliser pour adapter le fichier à un nouveau projet.

Objets principaux : un **Deployment** maintient N Pods identiques en fonctionnement ; un **Service** leur donne un nom DNS stable dans le cluster ; un **Ingress** associe un nom d'hôte externe à un Service (servi par Traefik). Les objets d'un même fichier sont séparés par `---`.

## Deployment

| Champ | Rôle | À modifier quand |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-app` | Nom du Deployment ; cible de `rollout restart` | À définir pour chaque projet |
| `metadata.namespace` | Namespace dans lequel vit l'objet | Toujours = namespace du projet |
| `spec.replicas: 1` | Nombre de Pods. Gardez 1 : le code et les données sont sur le disque d'un seul nœud | Jamais sur un homelab à nœud unique |
| `spec.selector.matchLabels` | Quels Pods ce Deployment possède | Doit être exactement égal à `template.metadata.labels`, sinon `apply` échoue avec `selector does not match template labels` |
| `template.metadata.labels: app: <PROJECT_NAME>` | Label apposé sur les Pods ; le Service les sélectionne avec | Doit correspondre au `selector` du Service |
| `containers[php].image` | Image PHP-FPM construite à partir du Dockerfile du projet | Nouveau nom/tag d'image |
| `imagePullPolicy: Never` | Ne jamais tirer depuis un registre ; utiliser l'image containerd locale | Retirer si l'image vient d'un registre |
| `workingDir: /var/www/html` | Répertoire par défaut du processus PHP | Rarement |
| `ports.containerPort: 9000` | Documentation uniquement (port FPM) ; n'ouvre rien | Rarement |
| `containers[nginx].image: nginx:alpine` | Nginx standard | Figer une version pour la reproductibilité |
| `ports.containerPort: 80` | Documentation uniquement | Si Nginx écoute ailleurs |
| `volumeMounts[code-volume]` | Répertoire du projet monté dans les deux conteneurs sur `/var/www/html` ; en lecture seule dans Nginx | Le chemin de montage doit correspondre au Dockerfile et à `root` dans `default.conf` |
| `volumeMounts[nginx-conf]` → `/etc/nginx/conf.d` | Monte le répertoire de configuration du site en lecture seule | Seulement si vous déplacez la configuration |

Les deux conteneurs partagent un même network namespace : Nginx atteint donc PHP-FPM sur `127.0.0.1:9000`.

## Volumes (`hostPath`)

`hostPath` associe un répertoire du disque du nœud au conteneur. C'est le type de volume le plus simple ; il lie le Pod à ce serveur, ce qui convient pour un nœud unique.

| Volume | `path` | `type` |
|---|---|---|
| `code-volume` | `/home/<SERVER_USER>/workspace/<PROJECT_GROUP>/<PROJECT_NAME>` | `DirectoryOrCreate` |
| `nginx-conf` | `.../<PROJECT_NAME>/k8s-local/nginx` | `Directory` |

- `Directory` : le chemin doit déjà exister, sinon le Pod reste `Pending` (`hostPath type check failed` dans `kubectl describe pod`). À utiliser pour ce qui doit impérativement être présent.
- `DirectoryOrCreate` : Kubernetes crée un répertoire vide s'il manque. Pratique, mais une faute de frappe vous donne silencieusement une racine de site vide.
- Ne montez que ce répertoire de configuration, pas l'arborescence complète de configuration Nginx du dépôt.
- TLS est terminé par Traefik : aucun certificat n'est donc monté dans Nginx.

## Service

| Champ | Rôle | À modifier quand |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-service` | Nom DNS dans le cluster `<PROJECT_NAME>-service.<PROJECT_NAME>.svc.cluster.local` | Par projet ; doit être référencé à l'identique dans l'Ingress |
| `spec.selector: app: <PROJECT_NAME>` | Pods qui reçoivent le trafic | Doit correspondre aux labels des Pods, sinon le Service n'a aucun endpoint |
| `ports.port: 80` | Port sur lequel le Service écoute | Si d'autres Pods appellent un autre port |
| `ports.targetPort: 80` | Port du conteneur vers lequel le trafic est transféré (Nginx) | Si Nginx écoute ailleurs |

Le type est `ClusterIP` par défaut : joignable uniquement à l'intérieur du cluster ; le trafic externe entre via l'Ingress.

## Ingress

| Champ | Rôle | À modifier quand |
|---|---|---|
| `traefik.../router.entrypoints: web,websecure` | Servir sur les entrypoints HTTP (80) et HTTPS (443) de Traefik | Utiliser `websecure` seul pour refuser le HTTP en clair |
| `traefik.../router.tls: "true"` | Active TLS sur le routeur ; le certificat auto-signé par défaut de Traefik est utilisé (avertissement du navigateur) | Ajouter un bloc `tls:`/un cert resolver pour un vrai certificat |
| `rules[0].host: <PROJECT_NAME>.<DOMAIN_BASE>` | Nom d'hôte routé vers ce projet ; deux Ingresses avec le même hôte entrent en collision | Toujours unique par projet |
| `paths: / (Prefix)` | Tout ce qui est sous `/` | Seulement pour publier un sous-chemin |
| `backend.service.name/port` | Service cible et son port | Doit être égal au nom du Service et à son `port` ci-dessus |

## Vérifier

```bash
kubectl apply --dry-run=server -f app.yaml
kubectl -n <PROJECT_NAME> get endpoints <PROJECT_NAME>-service     # doit lister une IP de Pod
kubectl -n <PROJECT_NAME> describe ingress <PROJECT_NAME>-ingress
```

Des `ENDPOINTS` vides signifient que le sélecteur et les labels des Pods diffèrent.

Suite : [Manifeste de la base de données](database-manifest.md)
