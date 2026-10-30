# Deploying a Project End to End

Deploys one PHP/WordPress project (PHP-FPM + Nginx, MySQL, phpMyAdmin) to K3s using the manifests in [`examples/wordpress/`](../../examples/wordpress/). Prerequisites: working K3s with Traefik ([K3s install](../03-containers-and-k3s/k3s-install.md), [Ingress](../03-containers-and-k3s/ingress-traefik-first-app.md)), Docker, and the layout from [conventions](k8s-structure-conventions.md).

## 1. kubectl without sudo

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config && chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc && source ~/.bashrc
kubectl get nodes
```

## 2. File permissions on the project

PHP-FPM runs as `www-data` inside the container; you edit as `<SERVER_USER>`. Both need read/write on the project tree:

```bash
P=~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>
sudo chown -R <SERVER_USER>:<SERVER_USER> "$P"
sudo find "$P" -type d -exec chmod 775 {} +
sudo find "$P" -type f -exec chmod 664 {} +
find "$P" -name entrypoint.sh -exec chmod +x {} +
git -C "$P" config core.fileMode false
```

> **Warning:** ownership and modes are not stored in Git (except the exec bit). Repeat this step after every fresh clone. If uploads fail with `Permission denied`, the container user's UID does not match the owner/group of `wp-content/uploads`; align the container user's UID/GID with <SERVER_USER> in the Dockerfile (or make `uploads/` group-writable for the container's group).

## 3. Local-only directories

```bash
mkdir -p $P/k8s-local/nginx $P/k8s-local/mysql-data
printf 'k8s-local/\nwp-cli.phar\n*.sql\n' >> $P/.git/info/exclude
```

`.git/info/exclude` is a per-clone `.gitignore` that is never pushed. `mysql-data` holds the database files, `nginx` the site config mounted into the pod.

## 4. Build the PHP image and hand it to K3s

K3s uses its own containerd image store, not Docker's. An image built with `docker build` is invisible to the cluster until imported (the manifest uses `imagePullPolicy: Never`).

```bash
cd $P                                  # build context must be the project root
docker build -t <PROJECT_NAME>-php:latest .
docker save <PROJECT_NAME>-php:latest | sudo k3s ctr images import -
sudo k3s crictl images | grep <PROJECT_NAME>-php
```

Repeat after any change to the `Dockerfile`, `php.ini` or other files copied into the image, then `kubectl rollout restart deployment/<PROJECT_NAME>-app -n <PROJECT_NAME>`.

## 5. Nginx site config

Mount only a dedicated file, never the repository's full config directory (a wrong file in `conf.d` makes Nginx fail or serve the wrong site).

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
        fastcgi_pass 127.0.0.1:9000;      # php container, same pod
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param HTTPS on;           # TLS ends at Traefik; without this WordPress loops redirects
        fastcgi_buffer_size 256k;
        fastcgi_buffers 4 512k;
        fastcgi_busy_buffers_size 512k;
    }
}
EOF
```

## 6. Namespace and Secret

```bash
kubectl create namespace <PROJECT_NAME>
kubectl -n <PROJECT_NAME> create secret generic <PROJECT_NAME>-secret \
  --from-literal=DB_ROOT_PASSWORD='<DB_PASSWORD>' \
  --from-literal=DB_NAME='<DB_NAME>'
```

`<DB_PASSWORD>` and `<DB_NAME>` are values you choose. The Secret is referenced by `db.yaml`; do not put passwords in manifests that go to Git.

## 7. Copy and adapt the manifests

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
grep -n '<[A-Z_]*>' "$M"/*.yaml          # must print nothing
```

Replace the `<real-...>` values with your own (`<repo>` is the path of this repository's checkout). Checklist before applying: unique Service names, `PMA_HOST` equals the DB Service name, `hostPath` points to the right project, hostnames are unique. Details: [manifests reference](manifests-reference/deployment-manifest.md).

## 8. Apply

```bash
kubectl apply -f "$M/db.yaml"
kubectl apply -f "$M/app.yaml"
kubectl apply -f "$M/phpmyadmin.yaml"
kubectl -n <PROJECT_NAME> get pods -w
```

Expected: `<PROJECT_NAME>-app` `2/2 Running`, `-db` and `-phpmyadmin` `1/1 Running`. The app may restart once while MySQL initialises (30-60 s on first start).

## 9. Hostnames on your workstation

Local domains are not in public DNS. On the client machine add to `/etc/hosts`:

```
<SERVER_IP>   <PROJECT_NAME>.<DOMAIN_BASE>
<SERVER_IP>   <PROJECT_NAME>-pma.<DOMAIN_BASE>
```

Browsers warn about Traefik's self-signed default certificate; accept the exception.

## Verify

```bash
curl -kI https://<PROJECT_NAME>.<DOMAIN_BASE>/
kubectl -n <PROJECT_NAME> get pods,svc,ingress
```

phpMyAdmin at `https://<PROJECT_NAME>-pma.<DOMAIN_BASE>/` (user `root`). To load existing content see [media and database migration](media-and-database-migration.md).

## Operations

| Action | Command |
|---|---|
| Logs of one container | `kubectl -n <PROJECT_NAME> logs deploy/<PROJECT_NAME>-app -c php` (or `-c nginx`) |
| Why a pod is Pending / failing | `kubectl -n <PROJECT_NAME> describe pod <pod>` (read `Events`) |
| Restart after Dockerfile/Nginx conf change | `kubectl -n <PROJECT_NAME> rollout restart deployment/<PROJECT_NAME>-app` |
| Apply edited manifest | `kubectl apply -f "$M/app.yaml"` |
| Roll back a bad change | `kubectl -n <PROJECT_NAME> rollout undo deployment/<PROJECT_NAME>-app` |
| Stop everything, keep data | `kubectl delete -R -f "$M"` (hostPath data stays on disk) |
| Remove the whole project | `kubectl delete namespace <PROJECT_NAME>` |

PHP/JS code changes need no restart (mounted from disk). `Dockerfile`/`php.ini` changes need steps 4 and a restart.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `ErrImageNeverPull` | Image not imported into containerd: repeat step 4 |
| Pod `Pending`, event `hostPath type check failed` | `type: Directory` path does not exist: `mkdir -p` it |
| `CrashLoopBackOff` | `kubectl logs <pod> -c php` / `-c nginx` |
| `exec: permission denied` on entrypoint | `chmod +x` the script (step 2) |
| Nginx: `conflicting server name` / `invalid number of arguments` | Wrong files in mounted `conf.d`; keep only `default.conf` |
| `Error establishing a database connection` | `DB_HOST` in `wp-config.php` is not `<PROJECT_NAME>-db-service` |
| phpMyAdmin login fails | `PMA_HOST` differs from the DB Service name, or wrong root password |
| All data lost after DB restart | `/var/lib/mysql` was not mounted from `hostPath`; restore from a dump |
| Site shows old version | Hard reload; opcache may need `kubectl delete pod` |

Next: [Manifests reference: Deployment](manifests-reference/deployment-manifest.md)
