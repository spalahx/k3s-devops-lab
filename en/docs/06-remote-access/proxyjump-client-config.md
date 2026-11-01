# ProxyJump Client Config

> **Status: not verified on real hardware.** The reference server this guide was checked against has no reverse tunnel service and no VPS gateway, so the steps on this page were written from documentation and have not been run end to end. Treat the commands as a starting point and verify each one.

Configures `~/.ssh/config` on the laptop so that one alias, `ssh home-server`, works both on the home network (direct) and away (through the VPS via the reverse tunnel). Requires the [reverse tunnel](reverse-ssh-tunnel-systemd.md) to be running. `ProxyJump` (`-J`) makes the SSH client open a connection to an intermediate host and tunnel the real connection through it.

## 1. Away-from-home entries

```
Host vps-gateway
    HostName <VPS_IP>
    User <VPS_USER>
    Port <SSH_PORT>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host home-server-remote
    HostName 127.0.0.1
    Port <TUNNEL_PORT>
    User <SERVER_USER>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ProxyJump vps-gateway
    # The VPS's loopback port has a different host key identity than the LAN address
    HostKeyAlias <SERVER_HOSTNAME>
    ServerAliveInterval 30
```

Here `127.0.0.1` is resolved on the VPS (the last hop), where the tunnel listens. Test:

```bash
ssh home-server-remote
```

> **Warning:** do not use `ProxyJump` to the home server's LAN IP (`<SERVER_IP>`) through the VPS: the VPS cannot reach the home LAN. The route is always laptop -> VPS -> tunnel port -> home server.

## 2. One alias for home and away

`ssh_config` uses the first value obtained for each option, so put the conditional block before the generic one. `Match ... exec` runs a command; if it succeeds the block applies.

```
# Reachable on the LAN -> connect directly
Match host home-server exec "nc -z -G 1 <SERVER_IP> <SSH_PORT> 2>/dev/null"
    HostName <SERVER_IP>
    Port <SSH_PORT>
    ProxyJump none

Host home-server
    HostName 127.0.0.1
    Port <TUNNEL_PORT>
    ProxyJump vps-gateway
    HostKeyAlias <SERVER_HOSTNAME>

Host home-server
    User <SERVER_USER>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 30
```

| Part | Why |
|---|---|
| `nc -z -G 1` | macOS: TCP probe with 1 s timeout. On Linux use `-w 1` instead of `-G 1` |
| `ProxyJump none` | Needed to cancel the jump, because the later `Host` block would otherwise add it |
| `HostKeyAlias` | Both paths present the same server key under one name, so `known_hosts` stays consistent and there are no host-key warnings |

The LAN check adds up to one second only when away from home. Hostname/port are taken from the first block that sets them.

## 3. IDE and tools

Any tool that reads `~/.ssh/config` works with the alias: VS Code/Cursor Remote-SSH (`home-server` appears in the host list; see [IDE Remote-SSH](../04-git-and-ide/ide-remote-ssh.md)), `scp`, `rsync`, `git` over SSH.

```bash
scp ./file.txt home-server:~/
rsync -av ./dist/ home-server:~/site/
```

One-off without editing the config:

```bash
ssh -J <VPS_USER>@<VPS_IP>:<SSH_PORT> -p <TUNNEL_PORT> <SERVER_USER>@127.0.0.1
```

For `kubectl` from the laptop, forward the API port over the same alias:

```bash
ssh -N -L 6443:127.0.0.1:6443 home-server
```

## Verify

```bash
ssh -G home-server | grep -Ei '^(hostname|port|proxyjump) '
ssh home-server hostname
```

At home `-G` shows `<SERVER_IP>` and no proxyjump; away it shows `127.0.0.1`, `<TUNNEL_PORT>` and `proxyjump vps-gateway`. Add `-v` to see which hops are taken.

| Symptom | Cause / fix |
|---|---|
| `Connection closed by UNKNOWN port 65535` | The tunnel is down; check the service on the home server |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | `HostKeyAlias` missing or the server was reinstalled; `ssh-keygen -R <SERVER_HOSTNAME>` |
| Always goes via VPS at home | LAN probe fails (firewall, wrong `<SERVER_IP>`, or `nc` flag for your OS) |
| `Permission denied (publickey)` | Laptop public key not in `<SERVER_USER>`'s `authorized_keys` on the home server |

Next: [GitLab CI pipeline](../07-cicd/gitlab-ci-petproject-pipeline.md)
