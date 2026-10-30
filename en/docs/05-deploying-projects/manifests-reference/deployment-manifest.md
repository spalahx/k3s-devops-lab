# Reference: Application Manifest (`app.yaml`)

Field-by-field notes for [`examples/wordpress/app.yaml`](../../../examples/wordpress/app.yaml): one pod with PHP-FPM and Nginx, a Service, and a Traefik Ingress. Use it when adapting the file to a new project.

Core objects: **Deployment** keeps N identical pods running; **Service** gives them a stable in-cluster DNS name; **Ingress** maps an external hostname to a Service (served by Traefik). Objects in one file are separated by `---`.

## Deployment

| Field | Does | Change when |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-app` | Deployment name; target of `rollout restart` | Always set per project |
| `metadata.namespace` | Namespace the object lives in | Always = project namespace |
| `spec.replicas: 1` | Number of pods. Keep 1: code and data are on one node's disk | Never on a single-node homelab |
| `spec.selector.matchLabels` | Which pods this Deployment owns | Must equal `template.metadata.labels` exactly, or `apply` fails with `selector does not match template labels` |
| `template.metadata.labels: app: <PROJECT_NAME>` | Label stuck on pods; the Service selects by it | Must match the Service `selector` |
| `containers[php].image` | PHP-FPM image built from the project's Dockerfile | New image name/tag |
| `imagePullPolicy: Never` | Never pull from a registry; use the local containerd image | Remove if the image comes from a registry |
| `workingDir: /var/www/html` | Default directory of the PHP process | Rarely |
| `ports.containerPort: 9000` | Documentation only (FPM port); does not open anything | Rarely |
| `containers[nginx].image: nginx:alpine` | Stock Nginx | Pin a version for reproducibility |
| `ports.containerPort: 80` | Documentation only | If Nginx listens elsewhere |
| `volumeMounts[code-volume]` | Project directory mounted in both containers at `/var/www/html`; read-only in Nginx | Mount path must match the Dockerfile and `root` in `default.conf` |
| `volumeMounts[nginx-conf]` → `/etc/nginx/conf.d` | Mounts the site config directory read-only | Only if you move the config |

Both containers share one network namespace, so Nginx reaches PHP-FPM at `127.0.0.1:9000`.

## Volumes (`hostPath`)

`hostPath` maps a directory on the node's disk into the container. It is the simplest volume type and ties the pod to this server, which is fine for a single node.

| Volume | `path` | `type` |
|---|---|---|
| `code-volume` | `/home/<SERVER_USER>/workspace/<PROJECT_GROUP>/<PROJECT_NAME>` | `DirectoryOrCreate` |
| `nginx-conf` | `.../<PROJECT_NAME>/k8s-local/nginx` | `Directory` |

- `Directory`: path must already exist, otherwise the pod stays `Pending` (`hostPath type check failed` in `kubectl describe pod`). Use it for things that must be there.
- `DirectoryOrCreate`: Kubernetes creates an empty directory if missing. Convenient, but a typo silently gives you an empty site root.
- Mount only the one config directory, not the repository's full Nginx config tree.
- TLS is terminated by Traefik, so no certificates are mounted into Nginx.

## Service

| Field | Does | Change when |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-service` | In-cluster DNS name `<PROJECT_NAME>-service.<PROJECT_NAME>.svc.cluster.local` | Per project; must be referenced identically in the Ingress |
| `spec.selector: app: <PROJECT_NAME>` | Pods receiving traffic | Must match pod labels, otherwise the Service has no endpoints |
| `ports.port: 80` | Port the Service listens on | If other pods call a different port |
| `ports.targetPort: 80` | Container port traffic is forwarded to (Nginx) | If Nginx listens elsewhere |

Type is the default `ClusterIP`: reachable only inside the cluster; external traffic enters via Ingress.

## Ingress

| Field | Does | Change when |
|---|---|---|
| `traefik.../router.entrypoints: web,websecure` | Serve on Traefik's HTTP (80) and HTTPS (443) entrypoints | Use `websecure` only to refuse plain HTTP |
| `traefik.../router.tls: "true"` | Enable TLS on the router; Traefik's default self-signed cert is used (browser warning) | Add a `tls:` block/cert resolver for a real certificate |
| `rules[0].host: <PROJECT_NAME>.<DOMAIN_BASE>` | Hostname routed to this project; two Ingresses with the same host collide | Always unique per project |
| `paths: / (Prefix)` | Everything under `/` | Only to publish a sub-path |
| `backend.service.name/port` | Target Service and its port | Must equal the Service name and `port` above |

## Verify

```bash
kubectl apply --dry-run=server -f app.yaml
kubectl -n <PROJECT_NAME> get endpoints <PROJECT_NAME>-service     # must list a pod IP
kubectl -n <PROJECT_NAME> describe ingress <PROJECT_NAME>-ingress
```

Empty `ENDPOINTS` means the selector and pod labels differ.

Next: [Database manifest](database-manifest.md)
