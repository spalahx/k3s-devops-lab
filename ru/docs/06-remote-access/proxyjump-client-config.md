# Клиентская конфигурация ProxyJump

> **Статус: не проверено на реальном железе.** На эталонном сервере, с которым сверялось это руководство, нет службы обратного туннеля и VPS-шлюза, поэтому шаги на этой странице написаны по документации и не проходились от начала до конца. Считайте команды отправной точкой и проверяйте каждую.

Настраивает `~/.ssh/config` на ноутбуке так, чтобы один алиас, `ssh home-server`, работал и в домашней сети (напрямую), и вне дома (через VPS по reverse tunnel). Требуется работающий [reverse tunnel](reverse-ssh-tunnel-systemd.md). `ProxyJump` (`-J`) заставляет SSH-клиент подключиться к промежуточному хосту и провести через него основное соединение.

## 1. Записи для доступа вне дома

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
    # У loopback-порта VPS другой адрес, чем у LAN, поэтому фиксируем имя для host key
    HostKeyAlias <SERVER_HOSTNAME>
    ServerAliveInterval 30
```

`127.0.0.1` разрешается на VPS (последний хоп), где слушает туннель. Проверка:

```bash
ssh home-server-remote
```

> **Warning:** не указывайте через VPS `ProxyJump` на LAN-адрес домашнего сервера (`<SERVER_IP>`): VPS не видит домашнюю сеть. Маршрут всегда такой: ноутбук -> VPS -> порт туннеля -> домашний сервер.

## 2. Один алиас для дома и поездок

`ssh_config` использует первое полученное значение каждой опции, поэтому условный блок ставится перед общим. `Match ... exec` запускает команду; если она успешна, блок применяется.

```
# Доступен в LAN -> подключаемся напрямую
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

| Часть | Зачем |
|---|---|
| `nc -z -G 1` | macOS: проверка TCP с таймаутом 1 с. На Linux используйте `-w 1` вместо `-G 1` |
| `ProxyJump none` | Нужен, чтобы отменить jump: иначе его добавит следующий блок `Host` |
| `HostKeyAlias` | Оба пути показывают один и тот же ключ сервера под одним именем, `known_hosts` остаётся согласованным, предупреждений нет |

Проверка LAN добавляет до секунды только когда вы вне дома. Hostname/port берутся из первого блока, который их задаёт.

## 3. IDE и инструменты

Любой инструмент, читающий `~/.ssh/config`, работает с алиасом: VS Code/Cursor Remote-SSH (`home-server` появится в списке хостов; см. [IDE Remote-SSH](../04-git-and-ide/ide-remote-ssh.md)), `scp`, `rsync`, `git` по SSH.

```bash
scp ./file.txt home-server:~/
rsync -av ./dist/ home-server:~/site/
```

Разово, без правки конфига:

```bash
ssh -J <VPS_USER>@<VPS_IP>:<SSH_PORT> -p <TUNNEL_PORT> <SERVER_USER>@127.0.0.1
```

Для `kubectl` с ноутбука пробросьте порт API через тот же алиас:

```bash
ssh -N -L 6443:127.0.0.1:6443 home-server
```

## Verify

```bash
ssh -G home-server | grep -Ei '^(hostname|port|proxyjump) '
ssh home-server hostname
```

Дома `-G` показывает `<SERVER_IP>` и отсутствие proxyjump; вне дома — `127.0.0.1`, `<TUNNEL_PORT>` и `proxyjump vps-gateway`. Добавьте `-v`, чтобы увидеть, какие хопы используются.

| Симптом | Причина / решение |
|---|---|
| `Connection closed by UNKNOWN port 65535` | Туннель не работает; проверьте службу на домашнем сервере |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Нет `HostKeyAlias` или сервер переустановлен; `ssh-keygen -R <SERVER_HOSTNAME>` |
| Дома всё равно идёт через VPS | Проверка LAN не проходит (файрвол, неверный `<SERVER_IP>` или флаг `nc` для вашей ОС) |
| `Permission denied (publickey)` | Публичного ключа ноутбука нет в `authorized_keys` пользователя `<SERVER_USER>` на домашнем сервере |

Next: [GitLab CI pipeline](../07-cicd/gitlab-ci-petproject-pipeline.md)
