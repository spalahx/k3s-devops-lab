# Reverse SSH Tunnel as a systemd Service

Keeps a permanent outbound SSH connection from the home server to the VPS, publishing the home SSH port as `127.0.0.1:<TUNNEL_PORT>` on the VPS. Requires the [VPS gateway](vps-gateway-setup.md) with the tunnel user and key.

## 1. Test manually

Run on the home server:

```bash
ssh -N -R 127.0.0.1:<TUNNEL_PORT>:localhost:<SSH_PORT> \
    -i ~/.ssh/id_ed25519_tunnel \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -p <SSH_PORT> <TUNNEL_USER>@<VPS_IP>
```

| Flag | Meaning |
|---|---|
| `-N` | No remote command; only hold the forwarding |
| `-R 127.0.0.1:<TUNNEL_PORT>:localhost:<SSH_PORT>` | Listen on the VPS loopback at `<TUNNEL_PORT>`, forward to the home server's own SSH port |
| `ExitOnForwardFailure=yes` | Exit if the port cannot be bound, so systemd restarts it instead of leaving a dead tunnel |
| `ServerAliveInterval=30`, `ServerAliveCountMax=3` | Probe every 30 s, drop after 3 misses (about 90 s) so a half-dead connection is detected and re-established |

On the VPS, confirm the listener exists:

```bash
ss -tlnp | grep <TUNNEL_PORT>
```

Stop the test with `Ctrl+C` before creating the service.

> **Warning:** the option is `ServerAliveCountMax`. `ServerAliveCountAlive` does not exist and is rejected by ssh.

## 2. Create the systemd unit

Using plain `ssh` with keepalive is enough. `autossh` is an alternative wrapper, but with `ExitOnForwardFailure` plus `Restart=always` it adds nothing.

```bash
sudo nano /etc/systemd/system/vps-reverse-tunnel.service
```

```ini
[Unit]
Description=Reverse SSH tunnel to VPS gateway
After=network-online.target
Wants=network-online.target

[Service]
User=<SERVER_USER>
ExecStart=/usr/bin/ssh -N \
  -R 127.0.0.1:<TUNNEL_PORT>:localhost:<SSH_PORT> \
  -i /home/<SERVER_USER>/.ssh/id_ed25519_tunnel \
  -o IdentitiesOnly=yes \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o StrictHostKeyChecking=accept-new \
  -p <SSH_PORT> <TUNNEL_USER>@<VPS_IP>
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

`StrictHostKeyChecking=accept-new` records the VPS host key on first connect without a prompt (a service cannot answer one). To avoid trusting it blindly, connect once manually as `<SERVER_USER>` first and confirm the fingerprint.

## 3. Enable and start

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now vps-reverse-tunnel.service
```

## 4. Status and logs

```bash
systemctl status vps-reverse-tunnel.service
journalctl -u vps-reverse-tunnel.service -f
```

## Reconnect behaviour

| Event | Result |
|---|---|
| Home IP changes / Wi-Fi drops | Keepalive fails within ~90 s, ssh exits, systemd restarts it after `RestartSec` |
| Server reboot | Unit is enabled and starts after `network-online.target` |
| VPS reboot | ssh exits, systemd retries every 10 s until the VPS is back |
| Old session still held by the VPS | New attempt fails with `remote port forwarding failed`; with `ExitOnForwardFailure` it exits and retries until the VPS drops the stale session. If it never clears, set `ClientAliveInterval 30` and `ClientAliveCountMax 3` in the VPS `sshd_config` |

## Verify

On the VPS:

```bash
ss -tlnp | grep <TUNNEL_PORT>
ssh -p <TUNNEL_PORT> <SERVER_USER>@127.0.0.1
```

The second command must land on the home server's shell (check with `hostname`). Then set up the client side.

Common errors:

| Message | Cause / fix |
|---|---|
| `remote port forwarding failed for listen port` | Port busy on the VPS (stale session or another process), or `permitlisten` in `authorized_keys` does not match the `-R` address |
| `Permission denied (publickey)` on the VPS | Wrong key or permissions on `authorized_keys` / `.ssh` of `<TUNNEL_USER>` |
| `Permission denied (publickey)` on `127.0.0.1:<TUNNEL_PORT>` | The connecting user's public key is not in the home user's `authorized_keys` |
| Unit flaps in a restart loop | Read `journalctl -u vps-reverse-tunnel`; usually the VPS is unreachable or the port is taken |

Next: [ProxyJump client configuration](proxyjump-client-config.md)
