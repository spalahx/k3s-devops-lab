# Настройка VPS-шлюза

> **Статус: не проверено на реальном железе.** На эталонном сервере, с которым сверялось это руководство, нет службы обратного туннеля и VPS-шлюза, поэтому шаги на этой странице написаны по документации и не проходились от начала до конца. Считайте команды отправной точкой и проверяйте каждую.

Подготавливает небольшой арендованный VPS со статическим публичным IP, который служит точкой встречи для домашнего сервера за NAT или с динамическим IP. Пропустите, если у сервера уже есть публичный статический IP (например, облачный VPS) или вместо этого используется VPN (WireGuard/Tailscale).

Принцип: домашний сервер сам открывает исходящее SSH-соединение к VPS и публикует на нём свой SSH-порт (`ssh -R`). Клиенты подключаются к VPS, а тот пересылает трафик обратно через это соединение. Проброс портов на роутере не нужен, домашний IP может меняться.

Плейсхолдеры (помимо стандартных):

| Плейсхолдер | Значение |
|---|---|
| `<VPS_USER>` | Админ-пользователь на VPS (не root, с sudo) |
| `<TUNNEL_USER>` | Непривилегированный пользователь на VPS, нужный только для туннеля |
| `<TUNNEL_PORT>` | Порт на loopback VPS, ведущий на SSH домашнего сервера (например, `2222`) |

## 1. Арендовать VPS

- Подойдёт любой провайдер; хватит минимального тарифа (1 vCPU / 1 GB RAM) — VPS только ретранслирует SSH.
- Выберите ту же Ubuntu Server LTS, что и на домашнем сервере.
- Запишите публичный IP (`<VPS_IP>`) и начальные данные для входа.

## 2. Создать админ-пользователя и укрепить доступ

```bash
ssh root@<VPS_IP>
adduser <VPS_USER>
usermod -aG sudo <VPS_USER>
```

С ноутбука установите ключ и проверьте вход, прежде чем менять что-либо ещё:

```bash
ssh-copy-id <VPS_USER>@<VPS_IP>
ssh <VPS_USER>@<VPS_IP>
```

Затем примените ту же базовую защиту, что и на домашнем сервере: [SSH hardening](../02-security/ssh-hardening.md), [UFW](../02-security/firewall-ufw.md), [Fail2ban](../02-security/fail2ban.md). VPS напрямую доступен из интернета, поэтому это обязательно. Откройте только SSH-порт:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow <SSH_PORT>/tcp
sudo ufw enable
```

> **Warning:** при изменении настроек SSH и файрвола держите вторую сессию открытой и разрешайте SSH-порт до включения UFW.

## 3. Создать пользователя для туннеля

Отдельный пользователь ограничивает ущерб, если домашний сервер (или его ключ) скомпрометирован.

```bash
sudo adduser --disabled-password --gecos "" --shell /usr/sbin/nologin <TUNNEL_USER>
sudo install -d -m 700 -o <TUNNEL_USER> -g <TUNNEL_USER> /home/<TUNNEL_USER>/.ssh
```

Shell `nologin` подходит: для `ssh -N -R` оболочка не нужна.

## 4. Создать ключ туннеля на домашнем сервере

Отдельный ключ, не тот, что используется для Git:

```bash
ssh-keygen -t ed25519 -C "home-to-vps-tunnel" -f ~/.ssh/id_ed25519_tunnel -N ""
cat ~/.ssh/id_ed25519_tunnel.pub
```

Passphrase не задаётся, так как служба systemd должна стартовать без участия человека. Компенсируйте это ограничениями ключа на стороне VPS.

На VPS добавьте публичный ключ в `/home/<TUNNEL_USER>/.ssh/authorized_keys` одной строкой с ограничениями:

```
restrict,port-forwarding,permitlisten="127.0.0.1:<TUNNEL_PORT>" ssh-ed25519 AAAA...key... home-to-vps-tunnel
```

```bash
sudo chown <TUNNEL_USER>:<TUNNEL_USER> /home/<TUNNEL_USER>/.ssh/authorized_keys
sudo chmod 600 /home/<TUNNEL_USER>/.ssh/authorized_keys
```

| Опция | Эффект |
|---|---|
| `restrict` | Отключает PTY, forwarding агента/X11 и выполнение команд |
| `port-forwarding` | Возвращает только проброс портов |
| `permitlisten` | Ключу разрешён только один listener на VPS |

## 5. Настройки sshd на VPS

Проверьте действующие значения:

```bash
sudo sshd -T | grep -Ei 'allowtcpforwarding|gatewayports'
```

| Параметр | Значение | Когда |
|---|---|---|
| `AllowTcpForwarding` | `yes` (по умолчанию) | Нужен для `-R` |
| `GatewayPorts` | `no` (по умолчанию) | Рекомендуется. Порт туннеля слушает только `127.0.0.1` на VPS, клиенты заходят через [ProxyJump](proxyjump-client-config.md) |
| `GatewayPorts` | `clientspecified` или `yes` | Только если посторонние должны подключаться прямо на `<VPS_IP>:<TUNNEL_PORT>` |

Если прямой внешний доступ действительно нужен, измените `/etc/ssh/sshd_config` (или файл в `/etc/ssh/sshd_config.d/`):

```
GatewayPorts clientspecified
```

```bash
sudo sshd -t && sudo systemctl restart ssh
```

При `clientspecified` сторона туннеля должна использовать `-R 0.0.0.0:<TUNNEL_PORT>:localhost:<SSH_PORT>`, а значение `permitlisten` в `authorized_keys` должно совпадать с этим адресом. После этого ограничьте порт в UFW:

```bash
sudo ufw allow from 203.0.113.50 to any port <TUNNEL_PORT> proto tcp
```

> **Warning:** публично доступный порт туннеля выставляет SSH домашнего сервера под перебор паролей. Включите вход только по ключам на домашнем сервере и ограничьте исходные IP в UFW.

## Verify

```bash
# С домашнего сервера: вход по ключу работает (у пользователя туннеля нет shell, сессия сразу закроется)
ssh -i ~/.ssh/id_ed25519_tunnel <TUNNEL_USER>@<VPS_IP> -p <SSH_PORT>
# На VPS: конфиг sshd корректен, файрвол активен
sudo sshd -t && sudo ufw status
```

Next: [Reverse SSH tunnel как служба systemd](reverse-ssh-tunnel-systemd.md)
