# Firewall (UFW)

Blocks all incoming traffic except SSH and web ports using UFW (Uncomplicated Firewall, a front end for iptables/nftables). Set it up before changing the SSH port and before installing K3s, because K3s adds its own rules and some combinations break pod networking.

> **Warning:** `ufw enable` without an SSH rule cuts your session. Add the SSH rule first and keep a second session open.

## 1. Defaults

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

## 2. Allow SSH (before enabling)

Use the port that sshd listens on right now. During the port migration allow both:

```bash
sudo ufw allow 22/tcp comment 'SSH (temporary)'
sudo ufw allow <SSH_PORT>/tcp comment 'SSH'
```

Optional, LAN-only SSH (adapt the subnet; this is stricter and safe for a home server):

```bash
sudo ufw allow from 192.168.1.0/24 to any port <SSH_PORT> proto tcp comment 'SSH from LAN'
```

For a server with a public IP, restrict SSH to known addresses where possible, for example `sudo ufw allow from 203.0.113.10 to any port <SSH_PORT> proto tcp`.

## 3. Web ports

Traefik (the K3s ingress controller) serves HTTP/HTTPS on the node:

```bash
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
```

LAN-only alternative for a home server that should not be reachable from outside the subnet:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 80 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 443 proto tcp
```

## 4. K3s rules

On a single-node cluster nothing but 80/443 is needed from outside. Pods and services, however, talk through the node's own interfaces (`cni0`, `flannel.1`), and UFW's default policy drops that traffic. Allow the K3s pod and service networks (default CIDRs) explicitly:

```bash
sudo ufw allow from 10.42.0.0/16 to any comment 'K3s pods'
sudo ufw allow from 10.43.0.0/16 to any comment 'K3s services'
```

Only if you use the Kubernetes API or kubectl from another machine, or add more nodes:

| Port | Proto | Purpose | Open to |
|---|---|---|---|
| 6443 | tcp | Kubernetes API | laptop / agent nodes only |
| 10250 | tcp | kubelet metrics | other nodes only |
| 8472 | udp | flannel VXLAN | other nodes only |

```bash
sudo ufw allow from 192.168.1.0/24 to any port 6443 proto tcp comment 'K3s API from LAN'
```

## 5. Enable and check

```bash
sudo ufw enable
sudo ufw status numbered
sudo ufw status verbose
```

Expected: `Status: active`, `Default: deny (incoming), allow (outgoing)`, rules for `<SSH_PORT>`, 80, 443. When the SSH port migration is finished, delete the port-22 rule:

```bash
sudo ufw status numbered
sudo ufw delete allow 22/tcp
```

Delete by rule text, or by number from `status numbered` (numbers shift after each deletion).

## Gotchas

- **Docker bypasses UFW.** Ports published with `docker run -p 8080:80` are inserted into iptables ahead of UFW, so `ufw deny` does not hide them. Bind to localhost (`-p 127.0.0.1:8080:80`) or do not publish the port.
- **K3s adds its own iptables rules** (service load balancer for Traefik, kube-proxy NAT). Ports 80/443 reach Traefik through DNAT in the forward path; if after enabling UFW the sites time out while `curl localhost` works on the server, check `sudo ufw status` for the pod/service CIDR rules above and, if needed, set `DEFAULT_FORWARD_POLICY="ACCEPT"` in `/etc/default/ufw`, then `sudo ufw reload`.
- **Pods cannot resolve DNS / reach the internet after `ufw enable`:** the pod CIDR rule above is missing. `kubectl run -it --rm t --image=busybox --restart=Never -- nslookup kubernetes.default` is a quick test.
- **Order matters:** `ufw allow` before `ufw enable`, and the SSH port rule before changing the SSH port.
- **Other services need their own rules:** for example `sudo ufw allow samba` ([Samba](../09-optional-extras/samba-file-storage.md)), restricted to the LAN subnet.
- If K3s still misbehaves and the box is only reachable from a trusted LAN, the K3s docs' fallback is to disable UFW (`sudo ufw disable`) and rely on the router firewall. Prefer the rules above on any server with a public IP.

## Verify

```bash
sudo ufw status verbose
sudo ss -tlnp | grep -E ":<SSH_PORT>|:80 |:443 "
```

From the laptop: `ssh <SERVER_HOSTNAME>` works; `nc -zv <SERVER_IP> 3306` (a closed port) times out. After K3s is installed, `kubectl get pods -A` should stay all `Running`.

Next: [Fail2ban](fail2ban.md)
