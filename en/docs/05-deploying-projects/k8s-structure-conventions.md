# Directory and Naming Conventions: Code vs Manifests

Defines a two-repository layout on the server: project code in `~/workspace`, Kubernetes manifests in `~/k8s-infrastructure`. Use it before deploying the first project; skip only if you keep a single project with manifests inside its own repo.

## Layout

```
~/workspace/<PROJECT_GROUP>/              # code only (PHP/JS/themes), one Git repo per project
├── <PROJECT_NAME>/
│   ├── k8s-local/                        # local-only: nginx conf, mysql-data (excluded from Git)
│   └── ...
└── <OTHER_PROJECT>/

~/k8s-infrastructure/                     # manifests only, its own Git repo
├── system/                               # cluster-wide: Traefik settings, monitoring
│   ├── ingress/
│   └── monitoring/
└── projects/
    └── <PROJECT_GROUP>/
        ├── <PROJECT_NAME>/
        │   ├── db.yaml
        │   ├── phpmyadmin.yaml
        │   └── app.yaml
        └── <OTHER_PROJECT>/
            └── app.yaml
```

| Directory | Holds | Changes |
|---|---|---|
| `~/workspace/...` | Application code, history in the project's Git | Many times a day |
| `~/k8s-infrastructure/system/` | Cluster-wide config shared by every project | Rarely |
| `~/k8s-infrastructure/projects/` | One directory per deployed project | When hostnames, resources or images change |

Reasons for the split: code and runtime config change at different speeds, belong to different repos and owners, and manifests may reference infrastructure details (hostnames, resource sizes) that should not live in the application repo.

## Naming rules

1. Project directory names are **identical** in both trees (`~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>` and `~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>`). Shell helpers such as `kstart`/`kstop` (see [K3s aliases](../03-containers-and-k3s/k3s-productivity-aliases.md)) rely on this to find manifests from a short project name.
2. Every object name carries the project prefix; never use bare `db`, `app`, `redis`:

   | Object | Name |
   |---|---|
   | Namespace | `<PROJECT_NAME>` |
   | Deployments | `<PROJECT_NAME>-app`, `<PROJECT_NAME>-db`, `<PROJECT_NAME>-phpmyadmin` |
   | Services | `<PROJECT_NAME>-service`, `<PROJECT_NAME>-db-service`, `<PROJECT_NAME>-phpmyadmin-svc` |
   | Labels | `app: <PROJECT_NAME>`, `app: <PROJECT_NAME>-db` |
   | Hostnames | `<PROJECT_NAME>.<DOMAIN_BASE>`, `<PROJECT_NAME>-pma.<DOMAIN_BASE>` |
   | Local image | `<PROJECT_NAME>-php:latest` |

3. File names carry no order. `kubectl apply -R -f <dir>` applies everything at once; an app that starts before the database simply restarts until the DB is ready.

## One file or several

| Variant | Use when |
|---|---|
| One `app.yaml` (objects separated by `---`) | Single-component project |
| `deployment.yaml` / `service.yaml` / `ingress.yaml` | Group of small, simple projects |
| `db.yaml`, `phpmyadmin.yaml`, `app.yaml` | Multi-component project (WordPress + DB + admin UI); lets you restart or delete one component |

Kubernetes treats all variants identically. Ready-made WordPress files: [`examples/wordpress/`](../../examples/wordpress/).

## Namespaces

One namespace per project: `kubectl create namespace <PROJECT_NAME>`. The namespace gives name isolation (two projects may both contain a Service called `db`), a single-command cleanup (`kubectl delete namespace`), and per-project quotas. Set `metadata.namespace` in every manifest, so `kubectl apply -f` does not depend on the current context. Cluster-level components (Traefik, monitoring) stay in their own namespaces and are not managed here.

## Where to change what

| Task | Location |
|---|---|
| Edit application code | `~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/` |
| Change hostname, replicas, resources | `~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>/app.yaml` |
| Change DB settings | `.../db.yaml` |
| Global Traefik / monitoring | `~/k8s-infrastructure/system/` |

## Create the skeleton

```bash
mkdir -p ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/{nginx,mysql-data}
mkdir -p ~/k8s-infrastructure/system/{ingress,monitoring}
mkdir -p ~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>
cd ~/k8s-infrastructure && git init
```

Keep local-only data out of the code repo without touching its shared `.gitignore`:

```bash
printf 'k8s-local/\nwp-cli.phar\n*.sql\n' >> ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/.git/info/exclude
```

> **Warning:** editing code in `~/workspace` does not change a running container by itself. With code mounted via `hostPath` the change is visible immediately (restart only if opcache caches it); with code baked into an image you must rebuild the image and `kubectl rollout restart`.

## Verify

```bash
ls ~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>/
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME> && git status --short   # k8s-local/ must not be listed
```

`kubectl apply -R -f <dir>` printing `no objects passed to apply` means the directory has no `.yaml` files or the path is wrong.

Next: [Generic deployment walkthrough](generic-deployment-walkthrough.md)
