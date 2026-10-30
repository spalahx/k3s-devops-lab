# VPS Gateway Setup

Prepares a small rented VPS with a static public IP that acts as a rendezvous point for a home server behind NAT or a dynamic IP. Skip this if the server already has a public static IP (for example, a cloud VPS), or if a VPN such as WireGuard/Tailscale is preferred.

How it works: the home server opens an outbound SSH connection to the VPS and publishes its own SSH port on the VPS (`ssh -R`). Clients connect to the VPS, which forwards the traffic back through that connection. No router port forwarding is needed, and the home IP can change.

Placeholders used here (in addition to the standard ones):

| Placeholder | Meaning |
|---|---|
| `<VPS_USER>` | Admin user on the VPS (non-root, sudo) |
| `<TUNNEL_USER>` | Unprivileged user on the VPS that only holds the tunnel |
| `<TUNNEL_PORT>` | Port on the VPS loopback that maps to the home server's SSH (e.g. `2222`) |

## 1. Rent the VPS

- Any provider works; the smallest plan (1 vCPU / 1 GB RAM) is enough, since it only relays SSH.
- Pick the same Ubuntu Server LTS as the home server.
- Note the public IP (`<VPS_IP>`) and the initial login.

## 2. Create an admin user and harden

```bash
ssh root@<VPS_IP>
adduser <VPS_USER>
usermod -aG sudo <VPS_USER>
```

From the laptop, install a key and verify login before touching anything else:

```bash
ssh-copy-id <VPS_USER>@<VPS_IP>
ssh <VPS_USER>@<VPS_IP>
```

Then apply the same baseline as the home server: [SSH hardening](../02-security/ssh-hardening.md), [UFW](../02-security/firewall-ufw.md), [Fail2ban](../02-security/fail2ban.md). The VPS is exposed to the internet directly, so this is not optional. Open only the SSH port:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow <SSH_PORT>/tcp
sudo ufw enable
```

> **Warning:** keep a second session open while changing SSH settings or firewall rules, and allow the SSH port before enabling UFW.

## 3. Create the tunnel user

A dedicated user limits the damage if the home server (or its key) is compromised.

```bash
sudo adduser --disabled-password --gecos "" --shell /usr/sbin/nologin <TUNNEL_USER>
sudo install -d -m 700 -o <TUNNEL_USER> -g <TUNNEL_USER> /home/<TUNNEL_USER>/.ssh
```

The `nologin` shell is fine: `ssh -N -R` does not need a shell.

## 4. Create the tunnel key on the home server

A separate key, not the one used for Git:

```bash
ssh-keygen -t ed25519 -C "home-to-vps-tunnel" -f ~/.ssh/id_ed25519_tunnel -N ""
cat ~/.ssh/id_ed25519_tunnel.pub
```

No passphrase is set because the systemd service must start unattended. Compensate by restricting the key on the VPS side.

On the VPS, add the public key to `/home/<TUNNEL_USER>/.ssh/authorized_keys` as a single line with restrictions:

```
restrict,port-forwarding,permitlisten="127.0.0.1:<TUNNEL_PORT>" ssh-ed25519 AAAA...key... home-to-vps-tunnel
```

```bash
sudo chown <TUNNEL_USER>:<TUNNEL_USER> /home/<TUNNEL_USER>/.ssh/authorized_keys
sudo chmod 600 /home/<TUNNEL_USER>/.ssh/authorized_keys
```

| Option | Effect |
|---|---|
| `restrict` | Disables PTY, agent/X11 forwarding, and command execution |
| `port-forwarding` | Re-enables only port forwarding |
| `permitlisten` | The key may open only this one listener on the VPS |

## 5. sshd settings on the VPS

Check the effective values:

```bash
sudo sshd -T | grep -Ei 'allowtcpforwarding|gatewayports'
```

| Setting | Value | When |
|---|---|---|
| `AllowTcpForwarding` | `yes` (default) | Required for `-R` |
| `GatewayPorts` | `no` (default) | Recommended. The tunnel port listens on `127.0.0.1` of the VPS only, and clients reach it through [ProxyJump](proxyjump-client-config.md) |
| `GatewayPorts` | `clientspecified` or `yes` | Only if third parties must connect straight to `<VPS_IP>:<TUNNEL_PORT>` |

If external direct access is really needed, change `/etc/ssh/sshd_config` (or a file in `/etc/ssh/sshd_config.d/`):

```
GatewayPorts clientspecified
```

```bash
sudo sshd -t && sudo systemctl restart ssh
```

With `clientspecified` the tunnel side must use `-R 0.0.0.0:<TUNNEL_PORT>:localhost:<SSH_PORT>`, and the `permitlisten` value in `authorized_keys` must match that address. Then restrict the port in UFW:

```bash
sudo ufw allow from 203.0.113.50 to any port <TUNNEL_PORT> proto tcp
```

> **Warning:** a publicly reachable tunnel port exposes the home server's SSH to brute-force attempts. Require key-only login on the home server and limit source IPs in UFW.

## Verify

```bash
# From the home server: key login works (tunnel user has no shell, so expect a closed session)
ssh -i ~/.ssh/id_ed25519_tunnel <TUNNEL_USER>@<VPS_IP> -p <SSH_PORT>
# On the VPS: sshd config is valid and the firewall is active
sudo sshd -t && sudo ufw status
```

Next: [Reverse SSH tunnel as a systemd service](reverse-ssh-tunnel-systemd.md)
