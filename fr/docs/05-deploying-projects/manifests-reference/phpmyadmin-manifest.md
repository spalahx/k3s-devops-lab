# Référence : manifeste phpMyAdmin (`phpmyadmin.yaml`)

Notes champ par champ sur [`examples/wordpress/phpmyadmin.yaml`](../../../examples/wordpress/phpmyadmin.yaml) : interface web pour la base de données du projet, sur son propre nom d'hôte. Ignorez-le pour les projets où `kubectl exec` et `mysql` suffisent, et ne l'exposez jamais sur un serveur joignable depuis Internet.

## Deployment

| Champ | Rôle | À modifier quand |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-phpmyadmin` | Nom du Deployment | Par projet |
| `selector` / `labels: app: <PROJECT_NAME>-phpmyadmin` | Relient Deployment, Pod et Service | Doivent correspondre entre eux et au sélecteur du Service |
| `image: phpmyadmin:5` | Image officielle tout-en-un (serveur web inclus ; aucun sidecar Nginx nécessaire) | Figer une version mineure plus récente si nécessaire |
| `PMA_HOST` | Serveur de base de données auquel se connecter | Doit être égal au `metadata.name` du Service de la base (`<PROJECT_NAME>-db-service`), casse comprise. Le DNS du cluster le résout ; n'utilisez ni IP ni `localhost` |
| `PMA_ABSOLUTE_URI` | URL publique à laquelle phpMyAdmin croit être servi | Doit être le vrai nom d'hôte HTTPS avec `/` final. Traefik termine TLS, donc le Pod voit du HTTP simple ; sans cela, les cookies de connexion sont rejetés et la session se réinitialise sans cesse |
| `PMA_STORAGE: ""` | Désactive la fonction de stockage de configuration (signets, historique), qui nécessite des tables supplémentaires | Retirer si vous créez ces tables |
| `containerPort: 80` | Documentation uniquement | Jamais |
| `resources.limits.memory` | Plafond pour qu'une requête lourde n'affame pas les autres projets | Augmenter pour les gros imports |

La connexion se fait par le formulaire : utilisateur `root`, mot de passe `DB_ROOT_PASSWORD` du Secret du projet. Le mot de passe n'est volontairement pas placé dans ce manifeste ; pour restreindre davantage l'accès, créez un utilisateur MySQL dédié plutôt que d'utiliser root.

## Service

| Champ | Rôle |
|---|---|
| `metadata.name: <PROJECT_NAME>-phpmyadmin-svc` | Backend référencé par l'Ingress |
| `selector: app: <PROJECT_NAME>-phpmyadmin` | Label du Pod |
| `port: 80` / `targetPort: 80` | Port du Service et port du serveur web de l'image |

## Ingress

| Champ | Rôle | À modifier quand |
|---|---|---|
| `router.entrypoints: web,websecure` | Servir sur les entrypoints HTTP et HTTPS | `websecure` seul pour du HTTPS uniquement |
| `router.tls: "true"` | TLS avec le certificat par défaut de Traefik | Mise en place d'un vrai certificat |
| `host: <PROJECT_NAME>-pma.<DOMAIN_BASE>` | Nom d'hôte d'administration ; doit correspondre à `PMA_ABSOLUTE_URI` et à l'entrée `/etc/hosts` du client | Par projet, unique |
| `backend.service` | Doit être égal au Service ci-dessus | Lors du renommage du Service |

> **Avertissement :** phpMyAdmin avec accès root est une cible de grande valeur. Ne rendez le nom d'hôte résolvable que sur votre LAN ou via un tunnel ([passerelle VPS](../../06-remote-access/vps-gateway-setup.md)), et supprimez le Deployment quand il n'est pas nécessaire : `kubectl -n <PROJECT_NAME> delete -f phpmyadmin.yaml`.

## Erreurs courantes

| Symptôme | Cause |
|---|---|
| `Cannot connect: invalid settings` | `PMA_HOST` diffère du nom du Service de la base |
| `Access denied for user 'root'` | Le mot de passe saisi diffère de celui défini à la première initialisation de la base |
| Boucle de redirection ou « la connexion se réinitialise » | `PMA_ABSOLUTE_URI` absent ou en `http://` |
| 404 de Traefik | L'hôte de l'Ingress ne correspond pas au nom d'hôte demandé |

## Vérifier

```bash
kubectl -n <PROJECT_NAME> get pods -l app=<PROJECT_NAME>-phpmyadmin
curl -kI https://<PROJECT_NAME>-pma.<DOMAIN_BASE>/
```

Suite : [Migration des médias et de la base de données](../media-and-database-migration.md)
