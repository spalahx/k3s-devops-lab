# Déployer un projet de bout en bout

Déploie un projet PHP/WordPress (PHP-FPM + Nginx, MySQL, phpMyAdmin) sur K3s à l'aide des manifestes de [`examples/wordpress/`](../../examples/wordpress/). Prérequis : un K3s fonctionnel avec Traefik ([installation de K3s](../03-containers-and-k3s/k3s-install.md), [Ingress](../03-containers-and-k3s/ingress-traefik-first-app.md)), Docker, et l'organisation décrite dans les [conventions](k8s-structure-conventions.md).

## 1. kubectl sans sudo

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config && chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc && source ~/.bashrc
kubectl get nodes
```

## 2. Droits sur les fichiers du projet

PHP-FPM s'exécute en tant que `www-data` dans le conteneur ; vous éditez en tant que `<SERVER_USER>`. Les deux doivent pouvoir lire et écrire dans l'arborescence du projet :

```bash
P=~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>
sudo chown -R <SERVER_USER>:<SERVER_USER> "$P"
sudo find "$P" -type d -exec chmod 775 {} +
sudo find "$P" -type f -exec chmod 664 {} +
find "$P" -name entrypoint.sh -exec chmod +x {} +
git -C "$P" config core.fileMode false
```

> **Avertissement :** le propriétaire et les modes ne sont pas stockés dans Git (sauf le bit d'exécution). Répétez cette étape après chaque nouveau clone. Si les envois de fichiers échouent avec `Permission denied`, l'UID de l'utilisateur du conteneur ne correspond pas au propriétaire/groupe de `wp-content/uploads` ; alignez l'UID/GID de l'utilisateur du conteneur sur <SERVER_USER> dans le Dockerfile (ou rendez `uploads/` accessible en écriture au groupe du conteneur).

## 3. Répertoires locaux uniquement

```bash
mkdir -p $P/k8s-local/nginx $P/k8s-local/mysql-data
printf 'k8s-local/\nwp-cli.phar\n*.sql\n' >> $P/.git/info/exclude
```

`.git/info/exclude` est un équivalent de `.gitignore` propre à chaque clone, qui n'est jamais poussé. `mysql-data` contient les fichiers de la base de données, `nginx` la configuration du site montée dans le Pod.

## 4. Construire l'image PHP et la fournir à K3s

K3s utilise son propre magasin d'images containerd, pas celui de Docker. Une image construite avec `docker build` reste invisible pour le cluster tant qu'elle n'est pas importée (le manifeste utilise `imagePullPolicy: Never`).

```bash
cd $P                                  # le contexte de build doit être la racine du projet
docker build -t <PROJECT_NAME>-php:latest .
docker save <PROJECT_NAME>-php:latest | sudo k3s ctr images import -
sudo k3s crictl images | grep <PROJECT_NAME>-php
```

Répétez après toute modification du `Dockerfile`, de `php.ini` ou d'autres fichiers copiés dans l'image, puis `kubectl rollout restart deployment/<PROJECT_NAME>-app -n <PROJECT_NAME>`.

## 5. Configuration du site Nginx

Montez uniquement un fichier dédié, jamais le répertoire de configuration complet du dépôt (un mauvais fichier dans `conf.d` fait échouer Nginx ou lui fait servir le mauvais site).

```bash
cat > $P/k8s-local/nginx/default.conf <<'EOF'
server {
    listen 80;
    server_name <PROJECT_NAME>.<DOMAIN_BASE>;
    root /var/www/html;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php$is_args$args;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass 127.0.0.1:9000;      # conteneur php, même Pod
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param HTTPS on;           # TLS se termine sur Traefik ; sans cela WordPress boucle sur les redirections
        fastcgi_buffer_size 256k;
        fastcgi_buffers 4 512k;
        fastcgi_busy_buffers_size 512k;
    }
}
EOF
```

## 6. Namespace et Secret

```bash
kubectl create namespace <PROJECT_NAME>
kubectl -n <PROJECT_NAME> create secret generic <PROJECT_NAME>-secret \
  --from-literal=DB_ROOT_PASSWORD='<DB_PASSWORD>' \
  --from-literal=DB_NAME='<DB_NAME>'
```

`<DB_PASSWORD>` et `<DB_NAME>` sont des valeurs que vous choisissez. Le Secret est référencé par `db.yaml` ; ne mettez pas de mots de passe dans des manifestes destinés à Git.

## 7. Copier et adapter les manifestes

```bash
M=~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>
mkdir -p "$M"
cp <repo>/examples/wordpress/db.yaml "$M/db.yaml"
cp <repo>/examples/wordpress/phpmyadmin.yaml "$M/phpmyadmin.yaml"
cp <repo>/examples/wordpress/app.yaml "$M/app.yaml"
sed -i \
  -e 's/<PROJECT_NAME>/<real-project-name>/g' \
  -e 's/<PROJECT_GROUP>/<real-group>/g' \
  -e 's/<SERVER_USER>/<real-user>/g' \
  -e 's/<DOMAIN_BASE>/<real-domain-base>/g' "$M"/*.yaml
grep -n '<[A-Z_]*>' "$M"/*.yaml          # ne doit rien afficher
```

Remplacez les valeurs `<real-...>` par les vôtres (`<repo>` est le chemin du clone de ce dépôt). Liste de contrôle avant l'application : noms de Service uniques, `PMA_HOST` égal au nom du Service de la base, `hostPath` pointant vers le bon projet, noms d'hôte uniques. Détails : [référence des manifestes](manifests-reference/deployment-manifest.md).

## 8. Appliquer

```bash
kubectl apply -f "$M/db.yaml"
kubectl apply -f "$M/app.yaml"
kubectl apply -f "$M/phpmyadmin.yaml"
kubectl -n <PROJECT_NAME> get pods -w
```

Résultat attendu : `<PROJECT_NAME>-app` en `2/2 Running`, `-db` et `-phpmyadmin` en `1/1 Running`. L'application peut redémarrer une fois pendant l'initialisation de MySQL (30 à 60 s au premier démarrage).

## 9. Noms d'hôte sur votre poste de travail

Les domaines locaux ne sont pas dans le DNS public. Sur la machine cliente, ajoutez à `/etc/hosts` :

```
<SERVER_IP>   <PROJECT_NAME>.<DOMAIN_BASE>
<SERVER_IP>   <PROJECT_NAME>-pma.<DOMAIN_BASE>
```

Les navigateurs avertissent à propos du certificat auto-signé par défaut de Traefik ; acceptez l'exception.

## Vérifier

```bash
curl -kI https://<PROJECT_NAME>.<DOMAIN_BASE>/
kubectl -n <PROJECT_NAME> get pods,svc,ingress
```

phpMyAdmin est disponible sur `https://<PROJECT_NAME>-pma.<DOMAIN_BASE>/` (utilisateur `root`). Pour charger un contenu existant, voir [migration des médias et de la base de données](media-and-database-migration.md).

## Exploitation

| Action | Commande |
|---|---|
| Logs d'un conteneur | `kubectl -n <PROJECT_NAME> logs deploy/<PROJECT_NAME>-app -c php` (ou `-c nginx`) |
| Pourquoi un Pod est Pending / en échec | `kubectl -n <PROJECT_NAME> describe pod <pod>` (lire `Events`) |
| Redémarrer après un changement du Dockerfile/de la conf Nginx | `kubectl -n <PROJECT_NAME> rollout restart deployment/<PROJECT_NAME>-app` |
| Appliquer un manifeste modifié | `kubectl apply -f "$M/app.yaml"` |
| Annuler un mauvais changement | `kubectl -n <PROJECT_NAME> rollout undo deployment/<PROJECT_NAME>-app` |
| Tout arrêter, conserver les données | `kubectl delete -R -f "$M"` (les données hostPath restent sur le disque) |
| Supprimer tout le projet | `kubectl delete namespace <PROJECT_NAME>` |

Les modifications du code PHP/JS ne nécessitent aucun redémarrage (monté depuis le disque). Les modifications de `Dockerfile`/`php.ini` nécessitent l'étape 4 et un redémarrage.

## Dépannage

| Symptôme | Cause / solution |
|---|---|
| `ErrImageNeverPull` | Image non importée dans containerd : répétez l'étape 4 |
| Pod `Pending`, événement `hostPath type check failed` | Le chemin `type: Directory` n'existe pas : créez-le avec `mkdir -p` |
| `CrashLoopBackOff` | `kubectl logs <pod> -c php` / `-c nginx` |
| `exec: permission denied` sur l'entrypoint | `chmod +x` sur le script (étape 2) |
| Nginx : `conflicting server name` / `invalid number of arguments` | Mauvais fichiers dans `conf.d` monté ; ne gardez que `default.conf` |
| `Error establishing a database connection` | `DB_HOST` dans `wp-config.php` n'est pas `<PROJECT_NAME>-db-service` |
| Échec de connexion à phpMyAdmin | `PMA_HOST` diffère du nom du Service de la base, ou mauvais mot de passe root |
| Toutes les données perdues après redémarrage de la base | `/var/lib/mysql` n'était pas monté depuis `hostPath` ; restaurez depuis un dump |
| Le site affiche une ancienne version | Rechargement forcé ; opcache peut nécessiter `kubectl delete pod` |

Suite : [Référence des manifestes : Deployment](manifests-reference/deployment-manifest.md)
