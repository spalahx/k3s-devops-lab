# Розгортання проєкту від початку до кінця

Розгортає один PHP/WordPress-проєкт (PHP-FPM + Nginx, MySQL, phpMyAdmin) у K3s за маніфестами з [`examples/wordpress/`](../../examples/wordpress/). Передумови: робочий K3s з Traefik ([встановлення K3s](../03-containers-and-k3s/k3s-install.md), [Ingress](../03-containers-and-k3s/ingress-traefik-first-app.md)), Docker і структура каталогів із [угод](k8s-structure-conventions.md).

## 1. kubectl без sudo

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config && chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc && source ~/.bashrc
kubectl get nodes
```

## 2. Права доступу до файлів проєкту

PHP-FPM працює від імені `www-data` усередині контейнера; редагуєте ви від імені `<SERVER_USER>`. Обом потрібні права читання й запису в дереві проєкту:

```bash
P=~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>
sudo chown -R <SERVER_USER>:<SERVER_USER> "$P"
sudo find "$P" -type d -exec chmod 775 {} +
sudo find "$P" -type f -exec chmod 664 {} +
find "$P" -name entrypoint.sh -exec chmod +x {} +
git -C "$P" config core.fileMode false
```

> **Попередження:** власник і режими доступу не зберігаються в Git (крім біта виконання). Повторюйте цей крок після кожного нового клонування. Якщо завантаження файлів завершується помилкою `Permission denied`, UID користувача контейнера не збігається з власником/групою `wp-content/uploads`; узгодьте UID/GID користувача контейнера з <SERVER_USER> у Dockerfile (або зробіть `uploads/` доступним для запису групі контейнера).

## 3. Каталоги лише для локального використання

```bash
mkdir -p $P/k8s-local/nginx $P/k8s-local/mysql-data
printf 'k8s-local/\nwp-cli.phar\n*.sql\n' >> $P/.git/info/exclude
```

`.git/info/exclude` — це `.gitignore` окремого клона, який ніколи не відправляється в репозиторій. У `mysql-data` лежать файли бази даних, у `nginx` — конфіг сайту, що монтується в под.

## 4. Збірка PHP-образу та передача його в K3s

K3s використовує власне сховище образів containerd, а не Docker. Образ, зібраний через `docker build`, невидимий для кластера, доки його не імпортовано (маніфест використовує `imagePullPolicy: Never`).

```bash
cd $P                                  # контекстом збірки має бути корінь проєкту
docker build -t <PROJECT_NAME>-php:latest .
docker save <PROJECT_NAME>-php:latest | sudo k3s ctr images import -
sudo k3s crictl images | grep <PROJECT_NAME>-php
```

Повторюйте після будь-якої зміни `Dockerfile`, `php.ini` чи інших файлів, що копіюються в образ, а потім виконуйте `kubectl rollout restart deployment/<PROJECT_NAME>-app -n <PROJECT_NAME>`.

## 5. Конфіг сайту Nginx

Монтуйте лише окремий файл, ніколи не весь каталог конфігурації з репозиторію (неправильний файл у `conf.d` призводить до збою Nginx або показує не той сайт).

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
        fastcgi_pass 127.0.0.1:9000;      # контейнер php, той самий под
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param HTTPS on;           # TLS завершується на Traefik; без цього WordPress зациклює редіректи
        fastcgi_buffer_size 256k;
        fastcgi_buffers 4 512k;
        fastcgi_busy_buffers_size 512k;
    }
}
EOF
```

## 6. Namespace і Secret

```bash
kubectl create namespace <PROJECT_NAME>
kubectl -n <PROJECT_NAME> create secret generic <PROJECT_NAME>-secret \
  --from-literal=DB_ROOT_PASSWORD='<DB_PASSWORD>' \
  --from-literal=DB_NAME='<DB_NAME>'
```

`<DB_PASSWORD>` і `<DB_NAME>` — значення, які ви обираєте самі. На Secret посилається `db.yaml`; не записуйте паролі в маніфести, що потрапляють у Git.

## 7. Копіювання та адаптація маніфестів

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
grep -n '<[A-Z_]*>' "$M"/*.yaml          # не має виводити нічого
```

Замініть значення `<real-...>` на власні (`<repo>` — шлях до клона цього репозиторію). Перелік перевірок перед застосуванням: унікальні назви Service, `PMA_HOST` дорівнює назві Service БД, `hostPath` вказує на потрібний проєкт, імена хостів унікальні. Подробиці: [довідник маніфестів](manifests-reference/deployment-manifest.md).

## 8. Застосування

```bash
kubectl apply -f "$M/db.yaml"
kubectl apply -f "$M/app.yaml"
kubectl apply -f "$M/phpmyadmin.yaml"
kubectl -n <PROJECT_NAME> get pods -w
```

Очікується: `<PROJECT_NAME>-app` у стані `2/2 Running`, `-db` і `-phpmyadmin` у стані `1/1 Running`. Застосунок може один раз перезапуститися, поки MySQL ініціалізується (30-60 с під час першого запуску).

## 9. Імена хостів на вашій робочій станції

Локальних доменів немає в публічному DNS. На клієнтській машині додайте в `/etc/hosts`:

```
<SERVER_IP>   <PROJECT_NAME>.<DOMAIN_BASE>
<SERVER_IP>   <PROJECT_NAME>-pma.<DOMAIN_BASE>
```

Браузери попереджатимуть про самопідписаний сертифікат Traefik за замовчуванням; підтвердьте виняток.

## Перевірка

```bash
curl -kI https://<PROJECT_NAME>.<DOMAIN_BASE>/
kubectl -n <PROJECT_NAME> get pods,svc,ingress
```

phpMyAdmin доступний за адресою `https://<PROJECT_NAME>-pma.<DOMAIN_BASE>/` (користувач `root`). Щоб завантажити наявний вміст, див. [міграцію медіафайлів і бази даних](media-and-database-migration.md).

## Експлуатація

| Дія | Команда |
|---|---|
| Логи одного контейнера | `kubectl -n <PROJECT_NAME> logs deploy/<PROJECT_NAME>-app -c php` (або `-c nginx`) |
| Чому под у стані Pending / збоїть | `kubectl -n <PROJECT_NAME> describe pod <pod>` (дивіться `Events`) |
| Перезапуск після зміни Dockerfile/конфіга Nginx | `kubectl -n <PROJECT_NAME> rollout restart deployment/<PROJECT_NAME>-app` |
| Застосування зміненого маніфесту | `kubectl apply -f "$M/app.yaml"` |
| Відкат невдалої зміни | `kubectl -n <PROJECT_NAME> rollout undo deployment/<PROJECT_NAME>-app` |
| Зупинити все, зберігши дані | `kubectl delete -R -f "$M"` (дані hostPath лишаються на диску) |
| Видалити весь проєкт | `kubectl delete namespace <PROJECT_NAME>` |

Зміни коду PHP/JS не потребують перезапуску (код монтується з диска). Зміни `Dockerfile`/`php.ini` потребують кроку 4 і перезапуску.

## Усунення несправностей

| Симптом | Причина / рішення |
|---|---|
| `ErrImageNeverPull` | Образ не імпортовано в containerd: повторіть крок 4 |
| Под у `Pending`, подія `hostPath type check failed` | Шлях із `type: Directory` не існує: створіть його через `mkdir -p` |
| `CrashLoopBackOff` | `kubectl logs <pod> -c php` / `-c nginx` |
| `exec: permission denied` в entrypoint | Виконайте `chmod +x` для скрипта (крок 2) |
| Nginx: `conflicting server name` / `invalid number of arguments` | Зайві файли в змонтованому `conf.d`; залиште лише `default.conf` |
| `Error establishing a database connection` | `DB_HOST` у `wp-config.php` не дорівнює `<PROJECT_NAME>-db-service` |
| Не вдається увійти в phpMyAdmin | `PMA_HOST` відрізняється від назви Service БД або неправильний пароль root |
| Усі дані втрачено після перезапуску БД | `/var/lib/mysql` не було змонтовано з `hostPath`; відновіть із дампа |
| Сайт показує стару версію | Жорстке перезавантаження сторінки; для opcache може знадобитися `kubectl delete pod` |

Далі: [Довідник маніфестів: Deployment](manifests-reference/deployment-manifest.md)
