# Ingress with Traefik and a First App

Deploys a throwaway Nginx app and exposes it as `http://<PROJECT_NAME>.<DOMAIN_BASE>` through the Traefik ingress controller that K3s installs by default. Run it once to confirm the whole chain (Deployment, Service, Ingress, DNS on the laptop) before deploying real projects.

## How it works

```
browser --> <SERVER_IP>:80 --> Traefik (kube-system) --> Ingress rule (Host header) --> Service --> Pod
```

| Object | Role |
|---|---|
| Deployment | Keeps N replicas of the Pod running |
| Service | Stable internal address for Pods matched by a label selector |
| Ingress | Rule "requests for host X go to Service Y"; Traefik picks it up automatically |

- K3s binds Traefik to ports 80/443 on the node (service `traefik`, type `LoadBalancer`, served by the built-in ServiceLB), so every project shares one IP and port; routing is by `Host` header.
- K3s marks Traefik as the default ingress class, so `ingressClassName` can be omitted.
- Nothing needs to be configured on Traefik itself.

## 1. Choose a hostname

`<PROJECT_NAME>.<DOMAIN_BASE>`, for example `demo.home.test`. Use a suffix that cannot clash with real DNS or multicast DNS: `.test` or a subdomain you own. Avoid `.local` (reserved for mDNS; on macOS lookups can stall for seconds).

## 2. Manifest

`test-app.yaml` on the server:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <PROJECT_NAME>-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <PROJECT_NAME>-web
  template:
    metadata:
      labels:
        app: <PROJECT_NAME>-web
    spec:
      containers:
      - name: web
        image: nginx:stable
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: <PROJECT_NAME>-web
spec:
  selector:
    app: <PROJECT_NAME>-web
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <PROJECT_NAME>-web
spec:
  rules:
  - host: <PROJECT_NAME>.<DOMAIN_BASE>
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: <PROJECT_NAME>-web
            port:
              number: 80
```

Replace the placeholders with real values (`sed` or an editor) before applying. YAML indentation uses spaces only; the `selector`/`labels` value must match in Deployment and Service.

```bash
kubectl apply -f test-app.yaml
kubectl get pods,svc,ingress
```

## 3. Hosts entry on the laptop

The laptop must resolve the name to the server. Add one line to the hosts file (needs `sudo`):

File: `/etc/hosts` (`sudo nano /etc/hosts`)

```
<SERVER_IP> <PROJECT_NAME>.<DOMAIN_BASE>
```

One IP, then one or more names separated by spaces; do not repeat the same name on several lines. Each new project needs its own name on that line. On macOS, if a new entry is ignored: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.

## Verify

```bash
ping -c1 <PROJECT_NAME>.<DOMAIN_BASE>        # shows <SERVER_IP>
curl -I http://<PROJECT_NAME>.<DOMAIN_BASE>  # HTTP/1.1 200 OK
```

Browser: `http://<PROJECT_NAME>.<DOMAIN_BASE>` shows "Welcome to nginx!". Without editing hosts:

```bash
curl -H "Host: <PROJECT_NAME>.<DOMAIN_BASE>" http://<SERVER_IP>/
```

| Symptom | Cause / fix |
|---|---|
| `404 page not found` (Traefik's page) | Ingress `host` differs from the name you typed, or no Ingress exists: `kubectl get ingress` |
| Name does not resolve | Hosts entry missing/typo; `ping` must show `<SERVER_IP>` |
| `ContainerCreating` for minutes / `ImagePullBackOff` | Server cannot pull the image; `kubectl describe pod <pod>` and check internet/DNS |
| `Pending` | Not enough CPU/RAM; see `Events` in `kubectl describe pod` |
| `error validating` on apply | Indentation or tabs in YAML |
| `502`/`Bad Gateway` | Service selector does not match Pod labels, or wrong `targetPort`; `kubectl get endpoints` must list a Pod IP |

## Cleanup

```bash
kubectl delete -f test-app.yaml
```

Remove the hosts line if the name will not be reused.

Next: [Shell productivity with Starship](shell-productivity-starship.md)
