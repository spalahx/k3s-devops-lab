# Migrer un site WordPress existant : médias et base de données

Transfère les fichiers envoyés et la base de données d'un site WordPress existant vers un projet déjà en cours d'exécution selon le [guide](generic-deployment-walkthrough.md). Le code provient de Git ; les fichiers envoyés et la base ne sont pas dans Git et doivent être copiés séparément.

## 1. Fichiers envoyés (`wp-content/uploads`)

Sur la machine source :

```bash
cd /path/to/source/wp-content
zip -rq uploads.zip uploads/
scp -P <SSH_PORT> uploads.zip <SERVER_USER>@<SERVER_IP>:~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/wp-content/
```

Sur le serveur :

```bash
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/wp-content
unzip -nq uploads.zip && rm uploads.zip      # -n : n'écrase jamais les fichiers existants
sudo chown -R <SERVER_USER>:<SERVER_USER> uploads
sudo find uploads -type d -exec chmod 775 {} + ; sudo find uploads -type f -exec chmod 664 {} +
```

Pour de très grandes bibliothèques, utilisez `rsync -av --progress -e "ssh -p <SSH_PORT>" uploads/ <SERVER_USER>@<SERVER_IP>:<path>/uploads/`, qui est reprenable. Comme le répertoire du projet est un montage `hostPath`, les fichiers sont immédiatement visibles dans le Pod.

## 2. Dump de la base de données

Exportez sur la source (à adapter à sa configuration) :

```bash
mysqldump --single-transaction --default-character-set=utf8mb4 -u<DB_USER> -p <DB_NAME> > dump.sql
```

`--single-transaction` fournit un instantané cohérent sans verrouiller les tables InnoDB. Gardez le dump hors de Git (`*.sql` dans `.git/info/exclude`).

## 3. Importer dans le Pod

Copiez le fichier dans le Pod et lisez-le localement ; c'est fiable pour les gros dumps, contrairement au flux via `kubectl exec -i ... < dump.sql`, qui peut s'interrompre sur des fichiers de plusieurs centaines de Mo.

```bash
NS=<PROJECT_NAME>
DB_POD=$(kubectl -n $NS get pods -l app=<PROJECT_NAME>-db -o jsonpath='{.items[0].metadata.name}')
kubectl -n $NS cp dump.sql $DB_POD:/tmp/dump.sql
kubectl -n $NS exec $DB_POD -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "source /tmp/dump.sql"'
kubectl -n $NS exec $DB_POD -- rm /tmp/dump.sql
```

Utiliser les variables `$MYSQL_ROOT_PASSWORD` / `$MYSQL_DATABASE` du Pod lui-même évite que le mot de passe apparaisse dans l'historique de votre shell. Les petits dumps peuvent être passés par un pipe : `kubectl -n $NS exec -i $DB_POD -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < dump.sql`.

| Erreur | Cause |
|---|---|
| `$DB_POD` vide | Le label de `-l` ne correspond pas aux `labels` de `db.yaml` |
| `ERROR 2002 Can't connect to local MySQL server` | MySQL est encore en cours d'initialisation (jusqu'à 60 s au premier démarrage) ; réessayez |
| `ERROR 1045 Access denied` | Mauvais mot de passe ; il est fixé à la première initialisation |
| `ERROR 1049 Unknown database` | Le nom diffère de `MYSQL_DATABASE` ; créez la base ou corrigez le nom |
| `ERROR 1273/1366 Unknown collation / incorrect string` | Dump issu d'une autre version de MySQL/MariaDB ; utilisez `utf8mb4_general_ci` ou modifiez les noms de collation du dump avec `sed` |
| `kubectl cp` bloqué / `unable to upgrade connection` | Transitoire ; réessayez. Vérifiez que le fichier source existe |

## 4. Changer les URL

Le dump contient l'ancienne URL du site dans `wp_options` et dans le contenu sérialisé. N'exécutez pas de simple remplacement de texte sur le fichier SQL : les données sérialisées de WordPress stockent les longueurs des chaînes, et une longueur modifiée corrompt la valeur. Utilisez wp-cli, qui gère la sérialisation.

```bash
# le répertoire du projet est monté sur /var/www/html, le fichier est donc visible dans le Pod
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>
curl -sLO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar   # exclu de Git
WP="kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-app -c php -- php /var/www/html/wp-cli.phar --allow-root --path=/var/www/html"
$WP search-replace 'https://<OLD_DOMAIN>' 'https://<PROJECT_NAME>.<DOMAIN_BASE>' --all-tables --dry-run
```

Relancez sans `--dry-run` une fois les décomptes corrects. `<OLD_DOMAIN>` est l'hôte d'origine du site. Si wp-cli n'est pas disponible, modifiez uniquement les deux options principales (les liens dans le contenu restent anciens) :

```sql
UPDATE wp_options SET option_value='https://<PROJECT_NAME>.<DOMAIN_BASE>' WHERE option_name IN ('siteurl','home');
```

Alternative sans modifier la base : les fixer dans `wp-config.php` (`WP_HOME`, `WP_SITEURL`, ci-dessous).

## 5. Valeurs de `wp-config.php`

```php
define('DB_NAME',     '<DB_NAME>');
define('DB_USER',     'root');
define('DB_PASSWORD', '<DB_PASSWORD>');
define('DB_HOST',     '<PROJECT_NAME>-db-service');   // le nom du Service, pas localhost
define('DB_CHARSET',  'utf8mb4');
define('WP_HOME',     'https://<PROJECT_NAME>.<DOMAIN_BASE>');
define('WP_SITEURL',  'https://<PROJECT_NAME>.<DOMAIN_BASE>');
// TLS se termine sur Traefik ; indique à WordPress que la requête était en HTTPS
if (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https') { $_SERVER['HTTPS'] = 'on'; }
```

`DB_HOST` est la panne la plus fréquente après une migration (`Error establishing a database connection`). Les extensions de cache/Redis reprises de la source peuvent référencer des hôtes inexistants ici ; désactivez-les jusqu'à ce que le site se charge (`wp-content/object-cache.php` peut être renommé).

## 6. Droits et caches

```bash
# $WP est défini à l'étape 4
$WP cache flush
$WP rewrite flush
```

Les chemins accessibles en écriture (`uploads`, répertoires de cache) doivent l'être par `www-data` du conteneur ; relancez l'étape des droits du guide si les envois échouent. Les chemins absolus codés en dur de l'ancien hôte (par exemple `php_value error_log /old/path` dans `.htaccess`) doivent être remplacés par des chemins du conteneur tels que `/var/www/html/...`.

## Vérifier

```bash
kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-db -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "SHOW TABLES; SELECT option_name, option_value FROM wp_options WHERE option_name IN (\"siteurl\",\"home\");"'
curl -kI https://<PROJECT_NAME>.<DOMAIN_BASE>/wp-content/uploads/
```

Dans le navigateur : la page d'accueil se charge sans boucle de redirection, les images des anciens articles s'affichent, la connexion à `/wp-admin` fonctionne et l'envoi d'une image de test réussit. Le préfixe de table du dump (`wp_`) doit correspondre à `$table_prefix` dans `wp-config.php`.

Suite : [Liste de contrôle multi-projets](multi-project-checklist.md)
