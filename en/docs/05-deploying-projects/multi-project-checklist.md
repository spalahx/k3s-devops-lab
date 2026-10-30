# Running Several Projects Side by Side

Checklist for adding the second and every further project to one K3s node without collisions. Apply it every time before `kubectl apply` of a new project.

## Per-project checklist

| # | Item | Rule |
|---|---|---|
| 1 | Namespace | One per project: `kubectl create namespace <PROJECT_NAME>`; `metadata.namespace` set in every manifest |
| 2 | Object names | Project prefix on Deployments, Services, Ingresses (`<PROJECT_NAME>-db-service`, never `db`) |
| 3 | Labels | `app: <PROJECT_NAME>[-component]` unique; selectors match pod labels |
| 4 | Hostnames | `<PROJECT_NAME>.<DOMAIN_BASE>` and `<PROJECT_NAME>-pma.<DOMAIN_BASE>` unique; added to the client `/etc/hosts` (or DNS) |
| 5 | DB host | `DB_HOST` and `PMA_HOST` = this project's DB Service |
| 6 | hostPath | Own `k8s-local/mysql-data` and code directory per project; no two pods mount the same MySQL data dir |
| 7 | Local image | Unique tag `<PROJECT_NAME>-php:latest`, imported into containerd |
| 8 | Secret | Own `<PROJECT_NAME>-secret` with its own DB password |
| 9 | Ports | No `hostPort`/`NodePort` unless required; see below |
| 10 | Resources | `requests`/`limits` set on every container |

## Ports

Everything HTTP goes through Traefik on 80/443, routed by hostname, so projects need no public ports of their own. Avoid `hostPort` and `type: NodePort` for web apps. If a service must be reachable directly (SSH to a pod, a database client), assign NodePorts from the 30000-32767 range and record them in one list so they never collide:

| Project | Service | NodePort |
|---|---|---|
| `<PROJECT_NAME>` | `<PROJECT_NAME>-db-service` | `30001` (example) |

Prefer `kubectl port-forward` for ad hoc access: it opens nothing permanently.

## Resource limits

A single node shares RAM and CPU between all projects, and one runaway MySQL can trigger the node's OOM killer for everything.

```yaml
resources:
  requests: { cpu: 100m, memory: 256Mi }   # reserved for scheduling
  limits:   { memory: 1Gi }                # hard cap: exceeding it kills the container
```

Optionally cap a whole namespace:

```bash
kubectl -n <PROJECT_NAME> create quota <PROJECT_NAME>-quota --hard=requests.memory=2Gi,limits.memory=4Gi,pods=10
```

Pods that do not set requests/limits are then rejected, so set them in every manifest first. Check actual usage:

```bash
kubectl top pods -A          # needs metrics-server (bundled with K3s)
```

## Cross-namespace access (integration testing)

Services are reachable from any namespace via full DNS names:

```
<service>.<namespace>.svc.cluster.local
```

Example: project A's app reaching project B's API, or a test pod reaching a DB:

```bash
kubectl -n <PROJECT_NAME> run dns-test --rm -it --image=busybox:1.36 --restart=Never -- \
  wget -qO- http://<OTHER_PROJECT>-service.<OTHER_PROJECT>.svc.cluster.local/
```

Within one namespace the short name (`<PROJECT_NAME>-db-service`) is enough. Use the full form only for deliberate cross-project links; by default namespaces are not network-isolated. Restrict with `NetworkPolicy` if a project must not be reachable by others.

## Cleanup

```bash
kubectl delete namespace <PROJECT_NAME>                    # all objects of the project
sudo rm -rf ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/mysql-data   # database files (irreversible)
sudo k3s ctr images rm docker.io/library/<PROJECT_NAME>-php:latest
docker rmi <PROJECT_NAME>-php:latest
```

Then delete the `/etc/hosts` lines and the manifests directory under `~/k8s-infrastructure/projects/`. Deleting a namespace does not delete `hostPath` data; do a final `mysqldump` before removing it.

## Verify

```bash
kubectl get ns
kubectl get ingress -A          # hosts must all differ
kubectl get svc -A | grep -c db # each project has its own DB Service in its own namespace
kubectl top nodes
```

Next: [Roadmap checklist](../99-appendix/roadmap-checklist.md)
