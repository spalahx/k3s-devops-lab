# Міграція наявного сайту WordPress: медіафайли та база даних

Переносить завантаження та базу даних наявного сайту WordPress у проєкт, що вже працює за [покроковим посібником](generic-deployment-walkthrough.md). Код береться з Git; завантажені файли та БД у Git не зберігаються, їх потрібно копіювати окремо.

## 1. Завантажені файли (`wp-content/uploads`)

На вихідній машині:

```bash
cd /path/to/source/wp-content
zip -rq uploads.zip uploads/
scp -P <SSH_PORT> uploads.zip <SERVER_USER>@<SERVER_IP>:~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/wp-content/
```

На сервері:

```bash
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/wp-content
unzip -nq uploads.zip && rm uploads.zip      # -n: ніколи не перезаписувати наявні файли
sudo chown -R <SERVER_USER>:<SERVER_USER> uploads
sudo find uploads -type d -exec chmod 775 {} + ; sudo find uploads -type f -exec chmod 664 {} +
```

Для дуже великих бібліотек використовуйте `rsync -av --progress -e "ssh -p <SSH_PORT>" uploads/ <SERVER_USER>@<SERVER_IP>:<path>/uploads/`, який можна відновити після обриву. Оскільки каталог проєкту змонтовано через `hostPath`, файли одразу видимі поду.

## 2. Дамп бази даних

Експортуйте на вихідній машині (підлаштуйте під її конфігурацію):

```bash
mysqldump --single-transaction --default-character-set=utf8mb4 -u<DB_USER> -p <DB_NAME> > dump.sql
```

`--single-transaction` дає узгоджений знімок без блокування таблиць InnoDB. Не додавайте дамп у Git (`*.sql` у `.git/info/exclude`).

## 3. Імпорт у под

Скопіюйте файл у под і читайте його локально; це надійно для великих дампів, на відміну від потокової передачі через `kubectl exec -i ... < dump.sql`, яка може обриватися на файлах у кілька сотень мегабайтів.

```bash
NS=<PROJECT_NAME>
DB_POD=$(kubectl -n $NS get pods -l app=<PROJECT_NAME>-db -o jsonpath='{.items[0].metadata.name}')
kubectl -n $NS cp dump.sql $DB_POD:/tmp/dump.sql
kubectl -n $NS exec $DB_POD -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "source /tmp/dump.sql"'
kubectl -n $NS exec $DB_POD -- rm /tmp/dump.sql
```

Використання `$MYSQL_ROOT_PASSWORD` / `$MYSQL_DATABASE` самого пода не залишає пароль в історії вашої оболонки. Невеликі дампи можна передати через конвеєр: `kubectl -n $NS exec -i $DB_POD -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < dump.sql`.

| Помилка | Причина |
|---|---|
| `$DB_POD` порожня | Мітка в `-l` не збігається з `labels` у `db.yaml` |
| `ERROR 2002 Can't connect to local MySQL server` | MySQL ще ініціалізується (до 60 с під час першого запуску); повторіть спробу |
| `ERROR 1045 Access denied` | Неправильний пароль; його фіксують під час першої ініціалізації |
| `ERROR 1049 Unknown database` | Назва відрізняється від `MYSQL_DATABASE`; створіть базу або виправте назву |
| `ERROR 1273/1366 Unknown collation / incorrect string` | Дамп з іншої версії MySQL/MariaDB; використайте `utf8mb4_general_ci` або відредагуйте назви колації в дампі через `sed` |
| `kubectl cp` зависає / `unable to upgrade connection` | Тимчасова проблема; повторіть. Переконайтеся, що вихідний файл існує |

## 4. Зміна URL-адрес

Дамп містить стару адресу сайту в `wp_options` і серіалізованому вмісті. Не виконуйте звичайну текстову заміну в SQL-файлі: серіалізовані дані WordPress зберігають довжини рядків, і змінена довжина пошкоджує значення. Використовуйте wp-cli, який коректно обробляє серіалізацію.

```bash
# каталог проєкту змонтовано в /var/www/html, тож файл видно в поді
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>
curl -sLO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar   # виключено з Git
WP="kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-app -c php -- php /var/www/html/wp-cli.phar --allow-root --path=/var/www/html"
$WP search-replace 'https://<OLD_DOMAIN>' 'https://<PROJECT_NAME>.<DOMAIN_BASE>' --all-tables --dry-run
```

Повторіть без `--dry-run`, коли кількості замін виглядатимуть правильно. `<OLD_DOMAIN>` — це хост початкового сайту. Якщо wp-cli недоступний, змініть лише два основні параметри (посилання у вмісті залишаться старими):

```sql
UPDATE wp_options SET option_value='https://<PROJECT_NAME>.<DOMAIN_BASE>' WHERE option_name IN ('siteurl','home');
```

Альтернатива без редагування БД: зафіксуйте їх у `wp-config.php` (`WP_HOME`, `WP_SITEURL`, нижче).

## 5. Значення в `wp-config.php`

```php
define('DB_NAME',     '<DB_NAME>');
define('DB_USER',     'root');
define('DB_PASSWORD', '<DB_PASSWORD>');
define('DB_HOST',     '<PROJECT_NAME>-db-service');   // назва Service, а не localhost
define('DB_CHARSET',  'utf8mb4');
define('WP_HOME',     'https://<PROJECT_NAME>.<DOMAIN_BASE>');
define('WP_SITEURL',  'https://<PROJECT_NAME>.<DOMAIN_BASE>');
// TLS завершується на Traefik; повідомляємо WordPress, що запит був HTTPS
if (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https') { $_SERVER['HTTPS'] = 'on'; }
```

`DB_HOST` — найпоширеніша причина збою після міграції (`Error establishing a database connection`). Плагіни кешу/Redis, перенесені з джерела, можуть посилатися на хости, яких тут немає; вимкніть їх, доки сайт не завантажиться (`wp-content/object-cache.php` можна перейменувати).

## 6. Права доступу та кеші

```bash
# $WP визначено на кроці 4
$WP cache flush
$WP rewrite flush
```

Каталоги, доступні для запису (`uploads`, каталоги кешу), мають бути записуваними для `www-data` контейнера; якщо завантаження файлів не працює, повторіть крок із правами доступу з покрокового посібника. Жорстко прописані абсолютні шляхи старого хоста (наприклад, `php_value error_log /old/path` у `.htaccess`) потрібно змінити на шляхи контейнера, як-от `/var/www/html/...`.

## Перевірка

```bash
kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-db -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "SHOW TABLES; SELECT option_name, option_value FROM wp_options WHERE option_name IN (\"siteurl\",\"home\");"'
curl -kI https://<PROJECT_NAME>.<DOMAIN_BASE>/wp-content/uploads/
```

У браузері: головна сторінка завантажується без циклів перенаправлення, зображення зі старих записів відображаються, вхід у `/wp-admin` працює, а тестове завантаження зображення проходить успішно. Префікс таблиць у дампі (`wp_`) має збігатися з `$table_prefix` у `wp-config.php`.

Далі: [Контрольний список для кількох проєктів](multi-project-checklist.md)
