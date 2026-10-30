# Migrating an Existing WordPress Site: Media and Database

Moves uploads and the database of an existing WordPress site into a project already running per the [walkthrough](generic-deployment-walkthrough.md). Code comes from Git; uploads and the DB are not in Git and must be copied separately.

## 1. Uploads (`wp-content/uploads`)

On the source machine:

```bash
cd /path/to/source/wp-content
zip -rq uploads.zip uploads/
scp -P <SSH_PORT> uploads.zip <SERVER_USER>@<SERVER_IP>:~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/wp-content/
```

On the server:

```bash
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/wp-content
unzip -nq uploads.zip && rm uploads.zip      # -n: never overwrite existing files
sudo chown -R <SERVER_USER>:<SERVER_USER> uploads
sudo find uploads -type d -exec chmod 775 {} + ; sudo find uploads -type f -exec chmod 664 {} +
```

For very large libraries use `rsync -av --progress -e "ssh -p <SSH_PORT>" uploads/ <SERVER_USER>@<SERVER_IP>:<path>/uploads/`, which is resumable. Because the project directory is a `hostPath` mount, files are visible to the pod immediately.

## 2. Database dump

Export on the source (adjust to its setup):

```bash
mysqldump --single-transaction --default-character-set=utf8mb4 -u<DB_USER> -p <DB_NAME> > dump.sql
```

`--single-transaction` gives a consistent snapshot without locking InnoDB tables. Keep the dump out of Git (`*.sql` in `.git/info/exclude`).

## 3. Import into the pod

Copy the file into the pod and read it locally; this is reliable for large dumps, unlike streaming through `kubectl exec -i ... < dump.sql`, which can drop on multi-hundred-MB files.

```bash
NS=<PROJECT_NAME>
DB_POD=$(kubectl -n $NS get pods -l app=<PROJECT_NAME>-db -o jsonpath='{.items[0].metadata.name}')
kubectl -n $NS cp dump.sql $DB_POD:/tmp/dump.sql
kubectl -n $NS exec $DB_POD -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "source /tmp/dump.sql"'
kubectl -n $NS exec $DB_POD -- rm /tmp/dump.sql
```

Using the pod's own `$MYSQL_ROOT_PASSWORD` / `$MYSQL_DATABASE` keeps the password out of your shell history. Small dumps can be piped: `kubectl -n $NS exec -i $DB_POD -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < dump.sql`.

| Error | Cause |
|---|---|
| `$DB_POD` empty | Label in `-l` does not match `labels` in `db.yaml` |
| `ERROR 2002 Can't connect to local MySQL server` | MySQL still initialising (up to 60 s on first start); retry |
| `ERROR 1045 Access denied` | Wrong password; it is fixed at first initialisation |
| `ERROR 1049 Unknown database` | Name differs from `MYSQL_DATABASE`; create it or fix the name |
| `ERROR 1273/1366 Unknown collation / incorrect string` | Dump from a different MySQL/MariaDB version; use `utf8mb4_general_ci` or edit the dump's collation names with `sed` |
| `kubectl cp` hangs / `unable to upgrade connection` | Transient; retry. Confirm the source file exists |

## 4. Change URLs

The dump contains the old site URL in `wp_options` and serialized content. Do not run plain text replace on the SQL file: WordPress serialized data stores string lengths, and a changed length corrupts the value. Use wp-cli, which handles serialization.

```bash
# the project directory is mounted at /var/www/html, so the file is visible in the pod
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>
curl -sLO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar   # excluded from Git
WP="kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-app -c php -- php /var/www/html/wp-cli.phar --allow-root --path=/var/www/html"
$WP search-replace 'https://<OLD_DOMAIN>' 'https://<PROJECT_NAME>.<DOMAIN_BASE>' --all-tables --dry-run
```

Rerun without `--dry-run` once the counts look right. `<OLD_DOMAIN>` is the original site host. If wp-cli is not available, set the two core options only (content links stay old):

```sql
UPDATE wp_options SET option_value='https://<PROJECT_NAME>.<DOMAIN_BASE>' WHERE option_name IN ('siteurl','home');
```

Alternative without editing the DB: pin them in `wp-config.php` (`WP_HOME`, `WP_SITEURL`, below).

## 5. `wp-config.php` values

```php
define('DB_NAME',     '<DB_NAME>');
define('DB_USER',     'root');
define('DB_PASSWORD', '<DB_PASSWORD>');
define('DB_HOST',     '<PROJECT_NAME>-db-service');   // the Service name, not localhost
define('DB_CHARSET',  'utf8mb4');
define('WP_HOME',     'https://<PROJECT_NAME>.<DOMAIN_BASE>');
define('WP_SITEURL',  'https://<PROJECT_NAME>.<DOMAIN_BASE>');
// TLS ends at Traefik; tell WordPress the request was HTTPS
if (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https') { $_SERVER['HTTPS'] = 'on'; }
```

`DB_HOST` is the most common failure after migration (`Error establishing a database connection`). Cache/Redis plugins carried from the source may reference hosts that do not exist here; disable them until the site loads (`wp-content/object-cache.php` can be renamed).

## 6. Permissions and caches

```bash
# $WP is defined in step 4
$WP cache flush
$WP rewrite flush
```

Writable paths (`uploads`, cache directories) must be writable by the container's `www-data`; re-run the permission step from the walkthrough if uploads fail. Hardcoded absolute paths of the old host (for example `php_value error_log /old/path` in `.htaccess`) must be changed to container paths such as `/var/www/html/...`.

## Verify

```bash
kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-db -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "SHOW TABLES; SELECT option_name, option_value FROM wp_options WHERE option_name IN (\"siteurl\",\"home\");"'
curl -kI https://<PROJECT_NAME>.<DOMAIN_BASE>/wp-content/uploads/
```

In the browser: front page loads without redirect loops, images from old posts display, `/wp-admin` login works, and a test image upload succeeds. The table prefix in the dump (`wp_`) must match `$table_prefix` in `wp-config.php`.

Next: [Multi-project checklist](multi-project-checklist.md)
