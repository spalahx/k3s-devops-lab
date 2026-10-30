# Reference: Database Manifest (`db.yaml`)

Field-by-field notes for [`examples/wordpress/db.yaml`](../../../examples/wordpress/db.yaml): a MySQL Deployment with persistent storage and a ClusterIP Service. Use it when changing credentials, version, storage or resources.

## Deployment

| Field | Does | Change when |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-db` | Deployment name | Per project |
| `strategy.type: Recreate` | Stops the old pod before starting the new one. Two MySQL processes on one data directory corrupt it; the default `RollingUpdate` would briefly run both | Keep |
| `selector` / `template.labels: app: <PROJECT_NAME>-db` | Ties pod to Deployment and to the Service | Must match each other and the Service selector character for character |
| `image: mysql:8.4` | MySQL version. Pin it: a major-version change on an existing data directory fails to start | Upgrade deliberately, after a dump |
| `MYSQL_ROOT_PASSWORD` (from Secret) | Root password set at first initialisation only | Changing it later in the manifest does **not** change the stored password; use `ALTER USER` |
| `MYSQL_DATABASE` (from Secret) | Database created on first start | Must match `DB_NAME` in `wp-config.php` and the name used in dump imports |
| `args: --character-set-server=utf8mb4 --collation-server=utf8mb4_general_ci` | Full-Unicode default charset (emoji, 4-byte characters); `_ci` = case-insensitive comparison | Match your imported dump's collation |
| `containerPort: 3306` | Documentation only | Never |
| `resources.requests/limits` | Scheduler hint and memory cap; `limits.memory` OOM-kills the pod if exceeded | Tune per project size (see [multi-project checklist](../multi-project-checklist.md)) |

Env values come from a Secret (`secretKeyRef`) so no password sits in Git:

```bash
kubectl -n <PROJECT_NAME> create secret generic <PROJECT_NAME>-secret \
  --from-literal=DB_ROOT_PASSWORD='<DB_PASSWORD>' --from-literal=DB_NAME='<DB_NAME>'
```

Secret values are only base64-encoded, not encrypted; they protect against accidental commits, not against anyone with cluster access.

## Persistence

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

> **Warning:** without this volume (or with `mountPath` not exactly `/var/lib/mysql`) MySQL writes to the container's ephemeral layer. Any pod recreation (`rollout restart`, image update, node reboot, crash) wipes all data. This is the most destructive mistake in the whole setup.

Notes:
- The data directory must be empty on first start; MySQL refuses to initialise over files it did not create.
- Each project needs its own `mysql-data` directory. Sharing one between projects corrupts both.
- Exclude `k8s-local/` from Git; back up with `mysqldump`, not by copying the live directory.

## Service

| Field | Does | Change when |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-db-service` | DNS name used as DB host: `wp-config.php` `DB_HOST` and phpMyAdmin `PMA_HOST`. From other namespaces: `<PROJECT_NAME>-db-service.<PROJECT_NAME>.svc.cluster.local` | Per project; never name it just `db` |
| `selector: app: <PROJECT_NAME>-db` | Pods behind the Service | Must match pod labels |
| `port` / `targetPort: 3306` | Service port and container port | Rarely |

ClusterIP only: the database is not reachable from outside the cluster, which is intended. For an occasional external client use `kubectl port-forward`:

```bash
kubectl -n <PROJECT_NAME> port-forward svc/<PROJECT_NAME>-db-service 3306:3306
```

## Verify

```bash
kubectl -n <PROJECT_NAME> get pods -l app=<PROJECT_NAME>-db
kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-db -- \
  sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"'
ls ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/mysql-data | head
```

Next: [phpMyAdmin manifest](phpmyadmin-manifest.md)
