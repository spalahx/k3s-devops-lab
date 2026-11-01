# Samba File Storage

Exposes one folder of the server as a network drive (SMB) that macOS and Linux laptops can mount for drag-and-drop file exchange (SQL dumps, images, manifests). Optional: skip it on a cloud VPS (SMB must never face the internet) and when `scp`/`rsync`/IDE Remote-SSH is enough.

Samba keeps its own password database, separate from the Linux password and SSH keys. A correct SSH login does not grant SMB access until `smbpasswd` is set for that user.

## 1. Install

```bash
sudo apt update && sudo apt install -y samba
sudo systemctl enable --now smbd
systemctl status smbd --no-pager
```

`smbd` serves files; the optional `nmbd` (NetBIOS name discovery) is not needed when connecting by IP.

## 2. Create the shared folder

Share a dedicated directory, not the whole home directory: sharing `/home/<SERVER_USER>` would also expose `~/.ssh`, `~/.kube`, and shell history.

```bash
mkdir -p /home/<SERVER_USER>/share
chmod 0775 /home/<SERVER_USER>/share
```

## 3. Configure the share

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
sudo nano /etc/samba/smb.conf
```

Append at the end:

```ini
[share]
   comment = Server file exchange
   path = /home/<SERVER_USER>/share
   read only = no
   browsable = yes
   valid users = <SERVER_USER>
   create mask = 0664
   directory mask = 0775
   hosts allow = 192.168.1.0/24 127.0.0.1
   hosts deny = 0.0.0.0/0
```

| Option | Meaning |
|---|---|
| `[share]` | Share name used in the connection address |
| `path` | Real directory on the server |
| `read only = no` | Allow writes over the network |
| `valid users` | Only these Samba users may access this share |
| `create mask` / `directory mask` | Permissions for new files / directories created via SMB |
| `hosts allow` / `hosts deny` | Restrict to the local subnet (adjust the CIDR to the actual LAN) |

Optional global hardening, in the existing `[global]` section:

```ini
   server min protocol = SMB2
```

Validate:

```bash
testparm -s
```

## 4. Set the Samba password

The Linux user must already exist; `smbpasswd -a` only registers a Samba password for it.

```bash
sudo smbpasswd -a <SERVER_USER>
sudo systemctl restart smbd
```

Change it later with `sudo smbpasswd <SERVER_USER>`.

## 5. Open the firewall (LAN only)

Do not use `ufw allow samba` without a source: it opens SMB to everything that can reach the host. Limit it to the LAN subnet:

```bash
sudo ufw allow from 192.168.1.0/24 to any app Samba
sudo ufw status
```

## 6. Mount from the laptop

Use the server's static IP (`<SERVER_IP>`, see [static IP](../01-os-and-network/static-ip-and-networking.md)).

**macOS** (Finder -> Go -> Connect to Server, or `Cmd+K`):

```
smb://<SERVER_IP>/share
```

Choose "Registered User", enter `<SERVER_USER>` and the Samba password. The volume appears under Locations. From a terminal:

```bash
mkdir -p ~/mnt/server && mount_smbfs //<SERVER_USER>@<SERVER_IP>/share ~/mnt/server
```

**Linux**:

```bash
sudo apt install -y cifs-utils
printf 'username=<SERVER_USER>\npassword=<SAMBA_PASSWORD>\n' > ~/.smbcred && chmod 600 ~/.smbcred
sudo mkdir -p /mnt/server
sudo mount -t cifs //<SERVER_IP>/share /mnt/server -o credentials=$HOME/.smbcred,uid=$(id -u),gid=$(id -g)
```

`<SAMBA_PASSWORD>` is the password set in step 4. For a permanent mount, add the same options as an `/etc/fstab` line with `_netdev,nofail`.

## Verify

```bash
# On the server
sudo ss -tlnp | grep -E ':(139|445)\b'
smbclient -L localhost -U <SERVER_USER>
```

From the laptop: create a file in the mounted drive and check it on the server with `ls -l /home/<SERVER_USER>/share`.

## Gotchas

| Symptom | Cause / fix |
|---|---|
| Password rejected repeatedly | Typed the Linux/SSH password; use the one from `smbpasswd` |
| Share not visible | Syntax error in `smb.conf` (run `testparm`), or `hosts allow` does not include the client subnet |
| `Connection failed` / timeout | `smbd` not running, UFW rule missing, or client on another subnet |
| `Permission denied` on write | Linux permissions on `path` (`ls -ld`), `valid users`, or masks; fix with `chown`/`chmod 0775` |
| Share gone after reboot | Service not enabled: `systemctl is-enabled smbd` |
| Connection breaks when the server IP changes | Reserve the IP in the router or use netplan static addressing |

Next: [Glossary](../99-appendix/glossary.md)
