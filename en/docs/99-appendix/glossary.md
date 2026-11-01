# Glossary

| Term | Meaning |
|---|---|
| ClusterIP | Default Service type: a virtual IP reachable only inside the cluster |
| ConfigMap | Kubernetes object holding non-secret configuration, mounted as files or env vars |
| Container | Isolated process packaged with its dependencies, started from an image |
| containerd | Container runtime used by K3s to run Pods |
| CNI | Container Network Interface: plugin that gives Pods network access (Flannel in K3s) |
| Deployment | Object that keeps a desired number of identical Pods running and handles updates |
| DHCP reservation | Router setting that always hands the same LAN IP to a given MAC address |
| Docker | Tool to build images and run containers |
| ed25519 | Modern SSH key type; short and strong |
| Fail2ban | Service that bans IPs after repeated failed logins by reading logs |
| Flannel | Default K3s CNI plugin providing Pod networking |
| Grafana | Web UI for dashboards built from Prometheus and Loki data |
| Helm | Package manager for Kubernetes; installs applications as versioned charts |
| Helm chart | Packaged set of Kubernetes manifests with configurable values |
| hostPath | Volume type that mounts a directory of the node into a Pod |
| HWE | Hardware Enablement: newer kernel stack for an Ubuntu LTS release |
| Image | Read-only template a container is started from |
| Ingress | Object defining HTTP routing rules from hostnames/paths to Services |
| includeIf | Git config directive that loads extra settings depending on repository path |
| K3s | Lightweight Kubernetes distribution, single binary, bundles Traefik |
| kubeconfig | File with cluster address and credentials used by `kubectl` (`~/.kube/config`) |
| kubectl | Command-line client for the Kubernetes API |
| Kubernetes (K8s) | System that schedules and supervises containers across machines |
| Loki | Log storage system from Grafana Labs, indexed by labels |
| LTS | Long-term support release (Ubuntu LTS gets security updates for five years) |
| Manifest | YAML file describing Kubernetes objects |
| Namespace | Logical partition of a cluster; names and quotas are scoped per namespace |
| netplan | Ubuntu network configuration tool driven by YAML in `/etc/netplan/` |
| Node | A machine in the cluster; here, the single server |
| Pod | Smallest deployable unit: one or more containers sharing network and volumes |
| Prometheus | Time-series database that scrapes and stores metrics |
| Promtail | Agent that ships container and system logs to Loki |
| ProxyJump | SSH option (`-J`) connecting to a target through an intermediate host |
| PV / PVC | PersistentVolume and PersistentVolumeClaim: storage and a Pod's request for it |
| Remote-SSH | IDE feature that opens and edits a folder on a remote machine over SSH |
| Reverse SSH tunnel | Connection opened from the server to a VPS that exposes a server port on the VPS |
| rfkill | Utility that shows and toggles hardware and software radio blocks |
| Samba (SMB) | Protocol and server for network file shares usable from macOS and Linux |
| Secret | Kubernetes object for sensitive values such as passwords |
| Service | Stable internal address and load balancer in front of a set of Pods |
| SFTP | File transfer over SSH |
| sshd_config | OpenSSH server configuration file (`/etc/ssh/sshd_config`) |
| Starship | Cross-shell prompt that shows git, Kubernetes and other context |
| systemd | Init system and service manager; runs units such as the tunnel service |
| Traefik | Ingress controller/reverse proxy bundled with K3s |
| UFW | Uncomplicated Firewall: front end for iptables/nftables |
| VPS | Virtual private server rented from a cloud provider, usually with a fixed public IP |
| YAML | Indentation-based data format used for manifests and netplan |

Next: [Introduction](../00-overview/introduction.md)
