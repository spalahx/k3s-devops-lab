# Fail2ban

Bans IP addresses that repeatedly fail SSH logins, by adding temporary firewall rules. Complements key-only login ([SSH hardening](ssh-hardening.md)); install it after SSH uses `<SSH_PORT>`.

## 1. Install

```bash
sudo apt update && sudo apt install fail2ban -y
```

## 2. Configure the sshd jail

Do not edit `jail.conf`: package updates overwrite it. Put settings in `jail.local` (or a file in `jail.d/`), which overrides `jail.conf`.

```bash
sudo tee /etc/fail2ban/jail.local >/dev/null <<'CONF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 3
backend  = systemd
ignoreip = 127.0.0.1/8 ::1 192.168.1.0/24

[sshd]
enabled = true
port    = <SSH_PORT>
CONF
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban
```

| Setting | Meaning |
|---|---|
| `maxretry` | Failed attempts within `findtime` before a ban |
| `findtime` | Window in which failures are counted |
| `bantime` | Ban duration (`-1` = permanent; `bantime.increment = true` makes repeat offenders wait longer) |
| `ignoreip` | Never banned: loopback and your LAN. Adjust the subnet, and add your own fixed public IP if you have one |
| `backend = systemd` | Read the systemd journal (works even when `/var/log/auth.log` is absent) |

`port` must match the real SSH port. With the default 22 the jail would watch the log but ban the wrong port.

## 3. Operate

```bash
sudo fail2ban-client status                 # list of jails
sudo fail2ban-client status sshd            # banned IPs and counters
sudo fail2ban-client set sshd unbanip 203.0.113.50
sudo fail2ban-client set sshd banip 203.0.113.50
sudo tail -f /var/log/fail2ban.log
```

> **Warning:** testing the jail from your own laptop with wrong keys will ban your own IP (unless it is in `ignoreip`). Unban it from a second path or from the console.

## 4. Automatic security updates

`unattended-upgrades` installs security patches without manual work. It is usually pre-installed on Ubuntu Server:

```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades     # answer Yes
```

Settings live in `/etc/apt/apt.conf.d/50unattended-upgrades` (security origin is enabled by default). Automatic reboot is off by default; enable it only if short downtime at a set time is acceptable:

```
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
```

On a K3s node a reboot restarts all pods, so the default (no auto-reboot, reboot manually after kernel updates) is usually better.

## Verify

```bash
sudo fail2ban-client status sshd
```

Expected output contains `Journal matches: _SYSTEMD_UNIT=ssh.service + _COMM=sshd` (or `sshd.service`) and `Currently banned: 0`. Simulate: from a device not in `ignoreip`, fail login 3 times with a wrong key/user, then `status sshd` lists the IP. Check updates:

```bash
sudo unattended-upgrade --dry-run --debug | tail -5
systemctl status unattended-upgrades --no-pager | head -5
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Failed logins visible but no bans | `port` mismatch; wrong `backend`; read `/var/log/fail2ban.log` |
| `Journal matches` empty | `backend = systemd` missing, or SSH unit name differs: `systemctl list-units | grep ssh` |
| Banned yourself | `sudo fail2ban-client set sshd unbanip <IP>` from the console or another network |

Next: [Docker install](../03-containers-and-k3s/docker-install.md)
