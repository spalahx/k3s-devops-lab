# Развёртывание проекта от начала до конца

Разворачивает один PHP/WordPress-проект (PHP-FPM + Nginx, MySQL, phpMyAdmin) в K3s по манифестам из [`examples/wordpress/`](../../examples/wordpress/). Требуется: работающий K3s с Traefik ([установка K3s](../03-containers-and-k3s/k3s-install.md), [Ingress](../03-containers-and-k3s/ingress-traefik-first-app.md)), Docker и раскладка из [соглашений](k8s-structure-conventions.md).

## 1. kubectl без sudo

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config && chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc && source ~/.bashrc
kubectl get nodes
```

## 2. Права на файлы проекта

PHP-FPM внутри контейнера работает от `www-data`, а вы правите файлы от `<SERVER_USER>`. Обоим нужен доступ на чтение и запись:

```bash
P=~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>
sudo chown -R <SERVER_USER>:<SERVER_USER> "$P"
sudo find "$P" -type d -exec chmod 775 {} +
sudo find "$P" -type f -exec chmod 664 {} +
find "$P" -name entrypoint.sh -exec chmod +x {} +
git -C "$P" config core.fileMode false
```

> **Warning:** владелец и права не хранятся в Git (кроме бита исполнения). Повторяйте этот шаг после каждого нового клонирования. Если загрузка файлов даёт `Permission denied`, UID пользователя в контейнере не совпадает с владельцем/группой `wp-content/uploads`: выровняйте UID/GID контейнера с `<SERVER_USER>` в Dockerfile (или сделайте `uploads/` доступным на запись для группы контейнера).

## 3. Локальные каталоги

```bash
mkdir -p $P/k8s-local/nginx $P/k8s-local/mysql-data
printf 'k8s-local/\nwp-cli.phar\n*.sql\n' >> $P/.git/info/exclude
```

`.git/info/exclude` — персональный `.gitignore` конкретной копии репозитория, он никогда не публикуется. В `mysql-data` лежат файлы БД, в `nginx` — конфиг сайта, монтируемый в под.

## 4. Сборка PHP-образа и передача в K3s

K3s использует собственное хранилище образов containerd, а не Docker. Образ, собранный `docker build`, кластеру не виден, пока его не импортировать (в манифесте `imagePullPolicy: Never`).

```bash
cd $P                                  # контекст сборки: корень проекта
docker build -t <PROJECT_NAME>-php:latest .
docker save <PROJECT_NAME>-php:latest | sudo k3s ctr images import -
sudo k3s crictl images | grep <PROJECT_NAME>-php
```

Повторяйте после любых изменений `Dockerfile`, `php.ini` и других файлов, копируемых в образ, затем `kubectl rollout restart deployment/<PROJECT_NAME>-app -n <PROJECT_NAME>`.

## 5. Конфиг сайта для Nginx

Монтируйте только отдельный файл, а не весь каталог конфигов из репозитория (лишний файл в `conf.d` приводит к падению Nginx или показу не того сайта).

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
        fastcgi_pass 127.0.0.1:9000;      # контейнер php, тот же под
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param HTTPS on;           # TLS заканчивается на Traefik; без этого WordPress зацикливает редиректы
        fastcgi_buffer_size 256k;
        fastcgi_buffers 4 512k;
        fastcgi_busy_buffers_size 512k;
    }
}
EOF
```

## 6. Namespace и Secret

```bash
kubectl create namespace <PROJECT_NAME>
kubectl -n <PROJECT_NAME> create secret generic <PROJECT_NAME>-secret \
  --from-literal=DB_ROOT_PASSWORD='<DB_PASSWORD>' \
  --from-literal=DB_NAME='<DB_NAME>'
```

`<DB_PASSWORD>` и `<DB_NAME>` — значения, которые вы выбираете сами. На Secret ссылается `db.yaml`; не храните пароли в манифестах, которые попадают в Git.

## 7. Копирование и адаптация манифестов

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
grep -n '<[A-Z_]*>' "$M"/*.yaml          # не должно ничего вывести
```

Подставьте свои значения вместо `<real-...>` (`<repo>` — путь к локальной копии этого репозитория). Проверьте перед применением: имена Service уникальны, `PMA_HOST` равен имени Service БД, `hostPath` указывает на нужный проект, домены уникальны. Подробности: [справочник по манифестам](manifests-reference/deployment-manifest.md).

## 8. Применение

```bash
kubectl apply -f "$M/db.yaml"
kubectl apply -f "$M/app.yaml"
kubectl apply -f "$M/phpmyadmin.yaml"
kubectl -n <PROJECT_NAME> get pods -w
```

Ожидаемо: `<PROJECT_NAME>-app` `2/2 Running`, `-db` и `-phpmyadmin` `1/1 Running`. Приложение может один раз перезапуститься, пока MySQL инициализируется (30-60 с при первом старте).

## 9. Домены на рабочей машине

Локальных доменов нет в публичном DNS. На клиентской машине добавьте в `/etc/hosts`:

```
<SERVER_IP>   <PROJECT_NAME>.<DOMAIN_BASE>
<SERVER_IP>   <PROJECT_NAME>-pma.<DOMAIN_BASE>
```

Браузер предупредит о самоподписанном сертификате Traefik по умолчанию; подтвердите исключение.

## Verify

```bash
curl -kI https://<PROJECT_NAME>.<DOMAIN_BASE>/
kubectl -n <PROJECT_NAME> get pods,svc,ingress
```

phpMyAdmin: `https://<PROJECT_NAME>-pma.<DOMAIN_BASE>/` (пользователь `root`). Перенос существующего сайта: [миграция медиа и БД](media-and-database-migration.md).

## Эксплуатация

| Действие | Команда |
|---|---|
| Логи одного контейнера | `kubectl -n <PROJECT_NAME> logs deploy/<PROJECT_NAME>-app -c php` (или `-c nginx`) |
| Почему под в Pending / падает | `kubectl -n <PROJECT_NAME> describe pod <pod>` (раздел `Events`) |
| Перезапуск после правки Dockerfile/конфига Nginx | `kubectl -n <PROJECT_NAME> rollout restart deployment/<PROJECT_NAME>-app` |
| Применить изменённый манифест | `kubectl apply -f "$M/app.yaml"` |
| Откатить неудачное изменение | `kubectl -n <PROJECT_NAME> rollout undo deployment/<PROJECT_NAME>-app` |
| Остановить всё, сохранив данные | `kubectl delete -R -f "$M"` (данные hostPath остаются на диске) |
| Удалить проект целиком | `kubectl delete namespace <PROJECT_NAME>` |

Изменения PHP/JS-кода перезапуска не требуют (монтируются с диска). Изменения `Dockerfile`/`php.ini` требуют шага 4 и перезапуска.

## Диагностика

| Симптом | Причина / решение |
|---|---|
| `ErrImageNeverPull` | Образ не импортирован в containerd: повторите шаг 4 |
| Под `Pending`, событие `hostPath type check failed` | Путь с `type: Directory` не существует: создайте через `mkdir -p` |
| `CrashLoopBackOff` | `kubectl logs <pod> -c php` / `-c nginx` |
| `exec: permission denied` у entrypoint | `chmod +x` для скрипта (шаг 2) |
| Nginx: `conflicting server name` / `invalid number of arguments` | В смонтированном `conf.d` лишние файлы; оставьте только `default.conf` |
| `Error establishing a database connection` | `DB_HOST` в `wp-config.php` не равен `<PROJECT_NAME>-db-service` |
| Не входит в phpMyAdmin | `PMA_HOST` не совпадает с именем Service БД или неверный пароль root |
| Данные пропали после перезапуска БД | `/var/lib/mysql` не смонтирован из `hostPath`; восстановите из дампа |
| Сайт показывает старую версию | Жёсткая перезагрузка; для opcache может понадобиться `kubectl delete pod` |

Next: [Справочник по манифестам: Deployment](manifests-reference/deployment-manifest.md)
