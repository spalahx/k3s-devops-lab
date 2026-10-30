# Référence : manifeste de la base de données (`db.yaml`)

Notes champ par champ sur [`examples/wordpress/db.yaml`](../../../examples/wordpress/db.yaml) : un Deployment MySQL avec stockage persistant et un Service ClusterIP. À utiliser pour modifier les identifiants, la version, le stockage ou les ressources.

## Deployment

| Champ | Rôle | À modifier quand |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-db` | Nom du Deployment | Par projet |
| `strategy.type: Recreate` | Arrête l'ancien Pod avant de démarrer le nouveau. Deux processus MySQL sur un même répertoire de données le corrompent ; le `RollingUpdate` par défaut les ferait brièvement coexister | Conserver |
| `selector` / `template.labels: app: <PROJECT_NAME>-db` | Relie le Pod au Deployment et au Service | Doivent correspondre entre eux et au sélecteur du Service, caractère pour caractère |
| `image: mysql:8.4` | Version de MySQL. Figez-la : un changement de version majeure sur un répertoire de données existant empêche le démarrage | Mettre à niveau délibérément, après un dump |
| `MYSQL_ROOT_PASSWORD` (depuis le Secret) | Mot de passe root défini uniquement à la première initialisation | Le modifier plus tard dans le manifeste ne change **pas** le mot de passe stocké ; utilisez `ALTER USER` |
| `MYSQL_DATABASE` (depuis le Secret) | Base créée au premier démarrage | Doit correspondre à `DB_NAME` dans `wp-config.php` et au nom utilisé lors des imports de dump |
| `args: --character-set-server=utf8mb4 --collation-server=utf8mb4_general_ci` | Jeu de caractères par défaut Unicode complet (emoji, caractères sur 4 octets) ; `_ci` = comparaison insensible à la casse | Aligner sur la collation de votre dump importé |
| `containerPort: 3306` | Documentation uniquement | Jamais |
| `resources.requests/limits` | Indication pour l'ordonnanceur et plafond mémoire ; `limits.memory` fait tuer le Pod par l'OOM s'il est dépassé | Ajuster selon la taille du projet (voir [liste de contrôle multi-projets](../multi-project-checklist.md)) |

Les valeurs d'environnement proviennent d'un Secret (`secretKeyRef`), si bien qu'aucun mot de passe n'est dans Git :

```bash
kubectl -n <PROJECT_NAME> create secret generic <PROJECT_NAME>-secret \
  --from-literal=DB_ROOT_PASSWORD='<DB_PASSWORD>' --from-literal=DB_NAME='<DB_NAME>'
```

Les valeurs d'un Secret sont seulement encodées en base64, pas chiffrées ; elles protègent contre les commits accidentels, pas contre quiconque a accès au cluster.

## Persistance

```yaml
volumeMounts:
- name: mysql-storage
  mountPath: /var/lib/mysql
volumes:
- name: mysql-storage
  hostPath:
    path: /home/<SERVER_USER>/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/mysql-data
    type: DirectoryOrCreate
```

> **Avertissement :** sans ce volume (ou avec un `mountPath` différent de `/var/lib/mysql`), MySQL écrit dans la couche éphémère du conteneur. Toute recréation du Pod (`rollout restart`, mise à jour d'image, redémarrage du nœud, plantage) efface toutes les données. C'est l'erreur la plus destructrice de toute l'installation.

Remarques :
- Le répertoire de données doit être vide au premier démarrage ; MySQL refuse de s'initialiser sur des fichiers qu'il n'a pas créés.
- Chaque projet a besoin de son propre répertoire `mysql-data`. En partager un entre projets les corrompt tous les deux.
- Excluez `k8s-local/` de Git ; sauvegardez avec `mysqldump`, pas en copiant le répertoire en service.

## Service

| Champ | Rôle | À modifier quand |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-db-service` | Nom DNS utilisé comme hôte de la base : `DB_HOST` dans `wp-config.php` et `PMA_HOST` de phpMyAdmin. Depuis d'autres namespaces : `<PROJECT_NAME>-db-service.<PROJECT_NAME>.svc.cluster.local` | Par projet ; ne le nommez jamais simplement `db` |
| `selector: app: <PROJECT_NAME>-db` | Pods derrière le Service | Doit correspondre aux labels du Pod |
| `port` / `targetPort: 3306` | Port du Service et port du conteneur | Rarement |

ClusterIP uniquement : la base n'est pas joignable depuis l'extérieur du cluster, ce qui est voulu. Pour un client externe occasionnel, utilisez `kubectl port-forward` :

```bash
kubectl -n <PROJECT_NAME> port-forward svc/<PROJECT_NAME>-db-service 3306:3306
```

## Vérifier

```bash
kubectl -n <PROJECT_NAME> get pods -l app=<PROJECT_NAME>-db
kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-db -- \
  sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"'
ls ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/mysql-data | head
```

Suite : [Manifeste phpMyAdmin](phpmyadmin-manifest.md)
