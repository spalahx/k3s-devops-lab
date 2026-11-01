# SSH Hardening

Sets up key-only SSH login for a non-root sudo user and moves SSH from port 22 to `<SSH_PORT>`. Do it on every server that is reachable from outside its own room; for a purely local box it is still cheap and a good habit.

> **Warning:** to avoid locking yourself out, keep one working SSH session open for the whole procedure and test every change from a second terminal. If you use UFW, open `<SSH_PORT>` in it **before** switching the SSH port ([Firewall](firewall-ufw.md) step 1-3).

## 1. Non-root sudo user

Skip if the installer user `<SERVER_USER>` is already the one you work as. To add another admin:

```bash
sudo adduser <SERVER_USER>
sudo usermod -aG sudo <SERVER_USER>      # -a is mandatory: without it all other groups are removed
su - <SERVER_USER>
sudo whoami                              # must print: root
```

## 2. Key authentication from the laptop

On the laptop (macOS or Linux), one key per server or per purpose:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "<GIT_PERSONAL_EMAIL>" -f ~/.ssh/<SERVER_HOSTNAME>
```

- `ed25519` is a modern, short and fast key type.
- The comment (`-C`) is only a label. Set a passphrase; on macOS add `AddKeysToAgent yes` and `UseKeychain yes` to the `Host` block below to avoid retyping it.
- `~/.ssh/<SERVER_HOSTNAME>` is private and never leaves the laptop; `.pub` is public.

Copy the public key (asks for the account password once):

```bash
ssh-copy-id -i ~/.ssh/<SERVER_HOSTNAME>.pub <SERVER_USER>@<SERVER_IP>
```

If `ssh-copy-id` is missing (rare on macOS), use:

```bash
cat ~/.ssh/<SERVER_HOSTNAME>.pub | ssh <SERVER_USER>@<SERVER_IP> 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Add a client alias in `~/.ssh/config` on the laptop (port stays 22 for now):

```
Host <SERVER_HOSTNAME>
    HostName <SERVER_IP>
    User <SERVER_USER>
    IdentityFile ~/.ssh/<SERVER_HOSTNAME>
    IdentitiesOnly yes
    Port 22
```

Test, and do not continue until it logs in **without the account password**:

```bash
ssh <SERVER_HOSTNAME>
```

## 3. Harden `sshd`

Ubuntu reads drop-in files from `/etc/ssh/sshd_config.d/`, and the first value wins, so a drop-in prefixed `01-` overrides cloud-image defaults (`50-cloud-init.conf` may set `PasswordAuthentication yes`).

> **Warning:** do not put these lines into the main `/etc/ssh/sshd_config` instead. The `Include` of `sshd_config.d/*.conf` sits above them, so a `PasswordAuthentication yes` from `50-cloud-init.conf` still wins and password login stays enabled even though the main file says `no`. Always confirm with `sudo sshd -T` (below).

```bash
sudo tee /etc/ssh/sshd_config.d/01-hardening.conf >/dev/null <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
CONF
sudo sshd -t && echo OK        # silent or OK = syntax is valid
sudo systemctl reload ssh
```

Open a **new** terminal and confirm `ssh <SERVER_HOSTNAME>` still works. Check the effective values:

```bash
sudo sshd -T | grep -E "^(passwordauthentication|permitrootlogin|pubkeyauthentication)"
```

## 4. Change the port to `<SSH_PORT>`

Choose a free port above 1024 (for example `2222`). Apply in this order:

1. Allow it in the firewall first (if UFW is active): `sudo ufw allow <SSH_PORT>/tcp`.
2. Add the port in `sshd`, **keeping 22 for now**.
3. Test the new port from a second terminal.
4. Only then remove port 22.

SSH on Ubuntu is started by **socket activation**: `ssh.socket` owns the listening port. How the port is chosen depends on the release:

- **Ubuntu 26.04 (checked on a reference server):** the listening addresses are generated from `sshd_config` (`/run/systemd/generator/ssh.socket.d/addresses.conf`, created by `sshd-socket-generator`), so setting `Port` is enough. The unit file `systemctl cat ssh.socket` still shows `ListenStream=22`; that is expected and is overridden by the generated file.
- **Ubuntu 22.10 to 24.04:** the socket may ignore `Port` in `sshd_config`; set the port on the socket with a drop-in (see "Older releases" below).

On 26.04, keep both ports during the migration:

```bash
sudo tee /etc/ssh/sshd_config.d/02-port.conf >/dev/null <<'CONF'
Port 22
Port <SSH_PORT>
CONF
sudo sshd -t && echo OK
sudo systemctl daemon-reload      # the generator re-reads sshd_config
sudo systemctl restart ssh.socket
sudo ss -tlnp | grep -E "sshd|:22 |:<SSH_PORT> "
```

Both ports must show up in `ss`. If only 22 is listed, the generated socket was not refreshed: repeat `daemon-reload` and the restart, or use the drop-in from "Older releases".

**Older releases (22.10 to 24.04) and as a fallback:**

```bash
sudo mkdir -p /etc/systemd/system/ssh.socket.d
sudo tee /etc/systemd/system/ssh.socket.d/listen.conf >/dev/null <<'CONF'
[Socket]
ListenStream=
ListenStream=22
ListenStream=<SSH_PORT>
CONF
echo "Port <SSH_PORT>" | sudo tee /etc/ssh/sshd_config.d/02-port.conf
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo ss -tlnp | grep -E "sshd|:22 |:<SSH_PORT> "
```

- The empty `ListenStream=` line clears the default before the new values are added.
- If the system uses a classic service without the socket (`systemctl status ssh.socket` says `not-found`/`inactive`), only the `Port` line in `sshd_config` or its drop-in is needed, followed by `sudo systemctl restart ssh`.

Update the alias on the laptop (`Port <SSH_PORT>`) and test from a new terminal:

```bash
ssh -p <SSH_PORT> <SERVER_USER>@<SERVER_IP>
```

When it works repeatedly, drop port 22:

On 26.04 remove the `Port 22` line from `/etc/ssh/sshd_config.d/02-port.conf`; with the socket drop-in remove `ListenStream=22` from `listen.conf` instead. Then:

```bash
sudo sed -i '/^Port 22$/d' /etc/ssh/sshd_config.d/02-port.conf      # 26.04 (drop-in variant: edit listen.conf)
sudo systemctl daemon-reload && sudo systemctl restart ssh.socket
sudo ufw delete allow 22/tcp          # if you had opened it
```

## Verify

```bash
ssh <SERVER_HOSTNAME>                                  # key login on <SSH_PORT>
ssh -p 22 <SERVER_USER>@<SERVER_IP>                    # must fail (connection refused)
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password <SERVER_USER>@<SERVER_IP> -p <SSH_PORT>   # Permission denied
ssh root@<SERVER_IP> -p <SSH_PORT>                     # Permission denied
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Permission denied (publickey)` | On the server: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`; check with `ssh -v <SERVER_HOSTNAME>` that the right key is offered; ensure you copied the `.pub` file |
| Port change has no effect | `ss -tlnp` still shows only 22: re-run `daemon-reload` and `restart ssh.socket`; on releases up to 24.04 the socket drop-in is required |
| Password login still works | A drop-in (for example `50-cloud-init.conf`) sets `PasswordAuthentication yes` before your setting; check `sudo grep -ri passwordauth /etc/ssh/` and `sudo sshd -T` |
| Connection refused on new port | Not listening (`ss -tlnp`) or blocked: `sudo ufw status`, `sudo journalctl -u ssh -n 50` |
| Locked out | Needs console access: fix `/etc/ssh/sshd_config.d/*` and the socket drop-in, restart `ssh.socket` |

Next: [Firewall (UFW)](firewall-ufw.md)
