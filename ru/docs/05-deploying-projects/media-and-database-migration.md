# Перенос существующего WordPress-сайта: медиа и база данных

Переносит загрузки и базу данных существующего WordPress-сайта в проект, уже запущенный по [пошаговой инструкции](generic-deployment-walkthrough.md). Код берётся из Git; загрузки и БД в Git не хранятся и копируются отдельно.

## 1. Загрузки (`wp-content/uploads`)

На исходной машине:

```bash
cd /path/to/source/wp-content
zip -rq uploads.zip uploads/
scp -P <SSH_PORT> uploads.zip <SERVER_USER>@<SERVER_IP>:~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/wp-content/
```

На сервере:

```bash
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/wp-content
unzip -nq uploads.zip && rm uploads.zip      # -n: не перезаписывать существующие файлы
sudo chown -R <SERVER_USER>:<SERVER_USER> uploads
sudo find uploads -type d -exec chmod 775 {} + ; sudo find uploads -type f -exec chmod 664 {} +
```

Для очень больших библиотек используйте `rsync -av --progress -e "ssh -p <SSH_PORT>" uploads/ <SERVER_USER>@<SERVER_IP>:<path>/uploads/` — он докачивает при обрыве. Каталог проекта смонтирован как `hostPath`, поэтому файлы сразу видны в поде.

## 2. Дамп базы данных

Экспорт на источнике (подстройте под его окружение):

```bash
mysqldump --single-transaction --default-character-set=utf8mb4 -u<DB_USER> -p <DB_NAME> > dump.sql
```

`--single-transaction` даёт согласованный снимок без блокировки таблиц InnoDB. Не кладите дамп в Git (`*.sql` в `.git/info/exclude`).

## 3. Импорт в под

Скопируйте файл в под и прочитайте его локально: для больших дампов это надёжнее, чем передача через `kubectl exec -i ... < dump.sql`, которая может обрываться на файлах в сотни МБ.

```bash
NS=<PROJECT_NAME>
DB_POD=$(kubectl -n $NS get pods -l app=<PROJECT_NAME>-db -o jsonpath='{.items[0].metadata.name}')
kubectl -n $NS cp dump.sql $DB_POD:/tmp/dump.sql
kubectl -n $NS exec $DB_POD -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "source /tmp/dump.sql"'
kubectl -n $NS exec $DB_POD -- rm /tmp/dump.sql
```

Переменные `$MYSQL_ROOT_PASSWORD` / `$MYSQL_DATABASE` берутся внутри пода, поэтому пароль не попадает в историю shell. Небольшие дампы можно передать через pipe: `kubectl -n $NS exec -i $DB_POD -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < dump.sql`.

| Ошибка | Причина |
|---|---|
| `$DB_POD` пустая | Метка в `-l` не совпадает с `labels` в `db.yaml` |
| `ERROR 2002 Can't connect to local MySQL server` | MySQL ещё инициализируется (до 60 с при первом старте); повторите |
| `ERROR 1045 Access denied` | Неверный пароль; он фиксируется при первой инициализации |
| `ERROR 1049 Unknown database` | Имя отличается от `MYSQL_DATABASE`; создайте БД или исправьте имя |
| `ERROR 1273/1366 Unknown collation / incorrect string` | Дамп из другой версии MySQL/MariaDB; используйте `utf8mb4_general_ci` или поправьте названия collation в дампе через `sed` |
| `kubectl cp` зависает / `unable to upgrade connection` | Временный сбой; повторите. Проверьте, что исходный файл существует |

## 4. Смена URL

В дампе старый адрес сайта находится в `wp_options` и в сериализованном контенте. Не заменяйте текст в SQL-файле обычным поиском: сериализованные данные WordPress хранят длины строк, и изменение длины портит значение. Используйте wp-cli — он учитывает сериализацию.

```bash
# каталог проекта смонтирован в /var/www/html, поэтому файл виден внутри пода
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>
curl -sLO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar   # исключён из Git
WP="kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-app -c php -- php /var/www/html/wp-cli.phar --allow-root --path=/var/www/html"
$WP search-replace 'https://<OLD_DOMAIN>' 'https://<PROJECT_NAME>.<DOMAIN_BASE>' --all-tables --dry-run
```

Когда количество замен выглядит верно, повторите без `--dry-run`. `<OLD_DOMAIN>` — исходный домен сайта. Если wp-cli недоступен, замените хотя бы две основные опции (ссылки в контенте останутся старыми):

```sql
UPDATE wp_options SET option_value='https://<PROJECT_NAME>.<DOMAIN_BASE>' WHERE option_name IN ('siteurl','home');
```

Альтернатива без правки БД: зафиксировать их в `wp-config.php` (`WP_HOME`, `WP_SITEURL`, см. ниже).

## 5. Значения в `wp-config.php`

```php
define('DB_NAME',     '<DB_NAME>');
define('DB_USER',     'root');
define('DB_PASSWORD', '<DB_PASSWORD>');
define('DB_HOST',     '<PROJECT_NAME>-db-service');   // имя Service, не localhost
define('DB_CHARSET',  'utf8mb4');
define('WP_HOME',     'https://<PROJECT_NAME>.<DOMAIN_BASE>');
define('WP_SITEURL',  'https://<PROJECT_NAME>.<DOMAIN_BASE>');
// TLS заканчивается на Traefik; сообщаем WordPress, что запрос был по HTTPS
if (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https') { $_SERVER['HTTPS'] = 'on'; }
```

`DB_HOST` — самая частая причина сбоя после переноса (`Error establishing a database connection`). Плагины кэша/Redis, перенесённые с источника, могут ссылаться на несуществующие хосты; отключите их, пока сайт не загрузится (`wp-content/object-cache.php` можно переименовать).

## 6. Права и кэши

```bash
# $WP задан в шаге 4
$WP cache flush
$WP rewrite flush
```

Каталоги для записи (`uploads`, каталоги кэша) должны быть доступны на запись для `www-data` в контейнере; если загрузки не работают, повторите шаг с правами из пошаговой инструкции. Абсолютные пути старого сервера (например, `php_value error_log /old/path` в `.htaccess`) замените на пути внутри контейнера вида `/var/www/html/...`.

## Verify

```bash
kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-db -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "SHOW TABLES; SELECT option_name, option_value FROM wp_options WHERE option_name IN (\"siteurl\",\"home\");"'
curl -kI https://<PROJECT_NAME>.<DOMAIN_BASE>/wp-content/uploads/
```

В браузере: главная открывается без циклов редиректов, картинки старых записей отображаются, вход в `/wp-admin` работает, тестовая загрузка изображения проходит. Префикс таблиц в дампе (`wp_`) должен совпадать с `$table_prefix` в `wp-config.php`.

Next: [Чек-лист для нескольких проектов](multi-project-checklist.md)
