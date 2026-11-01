# Local vs cloud differences

The same stack runs on a home mini-PC or on a cloud VPS. This page lists what differs and which steps to skip or adapt.

## Comparison

| Aspect | Home mini-PC | Cloud VPS |
|---|---|---|
| OS install | USB stick, installer on the console | Pick Ubuntu Server LTS image in the provider panel |
| Address | LAN address from the router; needs a DHCP reservation or static netplan config | Public static IP assigned by provider |
| Router | Required: reservation, optionally port forwarding | None |
| Firewall | UFW on the host; router NAT adds a layer | UFW on the host plus the provider's cloud firewall (open the same ports in both) |
| Wi-Fi | Possible, but use Ethernet | Not applicable |
| Access | From LAN directly; from outside only through a VPS gateway or port forwarding | Direct over the internet, SSH key-only |
| DNS and domains | `/etc/hosts` entries or local DNS (`*.local` names) | Real DNS A records pointing to the VPS IP; TLS certificates possible |
| Power and cost | Hardware purchase, electricity, UPS optional; runs 24/7 at low wattage | Monthly fee scaled to CPU/RAM; no hardware |
| Exposure risk | Low unless ports are forwarded | High from the first minute: bots scan new IPs, harden before anything else |
| Resources | Fixed by your hardware | Resizable |

## What to skip or adapt

| Doc | Local mini-PC | Cloud VPS |
|---|---|---|
| [Install Ubuntu Server](../01-os-and-network/install-ubuntu-server.md) | Follow fully | Skip the installer; do the post-install updates, locale and timezone |
| [Static IP and networking](../01-os-and-network/static-ip-and-networking.md) | Follow fully | Skip; the provider already fixes the IP |
| [Security](../02-security/ssh-hardening.md) | Follow fully | Follow fully, first thing after login; mirror UFW rules in the cloud firewall |
| [Docker](../03-containers-and-k3s/docker-install.md), [K3s](../03-containers-and-k3s/k3s-install.md) | Follow | Follow |
| [Ingress and first app](../03-containers-and-k3s/ingress-traefik-first-app.md) | Hosts-file names | Use real DNS records instead of hosts-file entries |
| [VPS gateway](../06-remote-access/vps-gateway-setup.md), [reverse tunnel](../06-remote-access/reverse-ssh-tunnel-systemd.md), [ProxyJump](../06-remote-access/proxyjump-client-config.md) | Needed for access from outside the LAN | Skip, except ProxyJump if you add a private node behind the VPS |
| [Monitoring](../08-monitoring/helm-basics.md) | Follow | Follow; watch memory on small plans |
| [Samba](../09-optional-extras/samba-file-storage.md) | LAN only | Do not expose SMB to the internet; skip or tunnel over SSH |
| [Network troubleshooting](../99-appendix/troubleshooting-networking.md) | Applies | Not applicable |

> **Warning:** On a VPS, do not close your only SSH session while changing the SSH port or UFW rules. Open a second session and test the new settings before logging out; recovery requires the provider's web console.

Next: [OS install](../01-os-and-network/install-ubuntu-server.md)
