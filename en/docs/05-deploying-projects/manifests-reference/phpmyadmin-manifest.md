# Reference: phpMyAdmin Manifest (`phpmyadmin.yaml`)

Field-by-field notes for [`examples/wordpress/phpmyadmin.yaml`](../../../examples/wordpress/phpmyadmin.yaml): web UI for the project database, on its own hostname. Skip it for projects where `kubectl exec` and `mysql` are enough, or never expose it on a server reachable from the internet.

## Deployment

| Field | Does | Change when |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-phpmyadmin` | Deployment name | Per project |
| `selector` / `labels: app: <PROJECT_NAME>-phpmyadmin` | Link Deployment, pod and Service | Must match each other and the Service selector |
| `image: phpmyadmin:5` | Official all-in-one image (web server included; no Nginx sidecar needed) | Pin a newer minor if required |
| `PMA_HOST` | Database server to connect to | Must equal the `metadata.name` of the DB Service (`<PROJECT_NAME>-db-service`), case included. Cluster DNS resolves it; do not use an IP or `localhost` |
| `PMA_ABSOLUTE_URI` | Public URL phpMyAdmin believes it is served at | Must be the real HTTPS hostname with trailing `/`. Traefik terminates TLS, so the pod sees plain HTTP; without this, login cookies are rejected and the session keeps resetting |
| `PMA_STORAGE: ""` | Disables the configuration storage feature (bookmarks, history), which needs extra tables | Remove if you create those tables |
| `containerPort: 80` | Documentation only | Never |
| `resources.limits.memory` | Cap so a heavy query does not starve other projects | Raise for large imports |

Login is through the form: user `root`, password `DB_ROOT_PASSWORD` from the project Secret. The password is deliberately not placed in this manifest; to restrict access further, create a dedicated MySQL user instead of using root.

## Service

| Field | Does |
|---|---|
| `metadata.name: <PROJECT_NAME>-phpmyadmin-svc` | Backend referenced by the Ingress |
| `selector: app: <PROJECT_NAME>-phpmyadmin` | Pod label |
| `port: 80` / `targetPort: 80` | Service port and the image's web server port |

## Ingress

| Field | Does | Change when |
|---|---|---|
| `router.entrypoints: web,websecure` | Serve on HTTP and HTTPS entrypoints | `websecure` only for HTTPS-only |
| `router.tls: "true"` | TLS with Traefik's default certificate | Real certificate set-up |
| `host: <PROJECT_NAME>-pma.<DOMAIN_BASE>` | Admin hostname; must match `PMA_ABSOLUTE_URI` and the `/etc/hosts` entry on the client | Per project, unique |
| `backend.service` | Must equal the Service above | When renaming the Service |

> **Warning:** phpMyAdmin with root access is a high-value target. Keep the hostname resolvable only on your LAN or through a tunnel ([VPS gateway](../../06-remote-access/vps-gateway-setup.md)), and delete the Deployment when it is not needed: `kubectl -n <PROJECT_NAME> delete -f phpmyadmin.yaml`.

## Common mistakes

| Symptom | Cause |
|---|---|
| `Cannot connect: invalid settings` | `PMA_HOST` differs from the DB Service name |
| `Access denied for user 'root'` | Typed password differs from the one set at first DB initialisation |
| Redirect loop or "login resets" | `PMA_ABSOLUTE_URI` missing or uses `http://` |
| 404 from Traefik | Ingress host does not match the requested hostname |

## Verify

```bash
kubectl -n <PROJECT_NAME> get pods -l app=<PROJECT_NAME>-phpmyadmin
curl -kI https://<PROJECT_NAME>-pma.<DOMAIN_BASE>/
```

Next: [Media and database migration](../media-and-database-migration.md)
