# K3s Install

Installs K3s (a lightweight, single-binary Kubernetes distribution) as a systemd service with the bundled Traefik ingress controller, and configures `kubectl` for the regular user. K3s ships its own containerd, CoreDNS, Traefik and a service load balancer, so nothing else is required on a single node.

## 1. Install

```bash
curl -sfL https://get.k3s.io | sh -
```

The script detects the CPU architecture, installs `/usr/local/bin/k3s`, symlinks `kubectl`, creates the `k3s` systemd unit and starts it. Takes from 30 seconds to a few minutes.

Useful installer options (environment variables or flags after `sh -s -`):

| Option | Effect |
|---|---|
| `INSTALL_K3S_EXEC="--write-kubeconfig-mode 644"` | Make `/etc/rancher/k3s/k3s.yaml` world-readable so `kubectl` works without `sudo` (acceptable on a single-user box; otherwise use step 3) |
| `INSTALL_K3S_EXEC="--disable traefik"` | Do not deploy Traefik (only if you bring another ingress controller). Default install keeps it; the next pages rely on it |
| `INSTALL_K3S_VERSION=v1.36.4+k3s1` | Pin a specific version instead of the stable channel (the version used on the reference server; check the current stable release before installing) |

Example with an option:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
```

## 2. Check the node

```bash
sudo k3s kubectl get node
```

`STATUS` must be `Ready` (wait 20–30 seconds if `NotReady`). System pods take a couple of minutes to settle:

```bash
sudo k3s kubectl get pods -A
```

## 3. kubectl for the regular user

Copy the generated kubeconfig (contains cluster credentials) into the user's home:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config
```

The copied file points at `https://127.0.0.1:6443`, which is correct when `kubectl` runs on the server. To use `kubectl` from a laptop, copy the file there and replace `127.0.0.1` with `<SERVER_IP>` (port 6443 must be reachable; see the firewall and remote-access pages).

> **Warning:** the file is a snapshot. If K3s is reinstalled, certificates change and the copy stops working; copy it again.

## Verify

```bash
kubectl get node
kubectl get pods -A
kubectl -n kube-system get svc traefik
```

Expected: node `Ready`, pods `coredns`, `traefik`, `local-path-provisioner`, `metrics-server` in `Running`, and the `traefik` service of type `LoadBalancer` with `<SERVER_IP>` as external IP.

| Symptom | Fix |
|---|---|
| `permission denied` on `/etc/rancher/k3s/k3s.yaml` | `kubectl` is reading the root-only default; do step 3 and check `echo $KUBECONFIG` |
| `connection refused` | `sudo systemctl status k3s`; restart with `sudo systemctl restart k3s`; logs: `sudo journalctl -u k3s -f` |
| Node `NotReady` for minutes | Low RAM/disk or a port conflict on 80/443/6443; see the journal |
| Images built with Docker are not found by pods | K3s uses its own containerd; import: `docker save <image> \| sudo k3s ctr images import -` |

## Stop and uninstall

```bash
sudo systemctl stop k3s              # stop the cluster (data is kept)
sudo /usr/local/bin/k3s-killall.sh   # also kill all pod processes
sudo /usr/local/bin/k3s-uninstall.sh # remove K3s and all its cluster data
```

> **Warning:** `k3s-uninstall.sh` deletes the cluster state. Data stored in `hostPath` directories outside `/var/lib/rancher/k3s` is not touched.

Next: [Ingress with Traefik and a first app](ingress-traefik-first-app.md)
