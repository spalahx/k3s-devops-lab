# Клієнтська конфігурація ProxyJump

Налаштовує `~/.ssh/config` на ноутбуці так, щоб один псевдонім, `ssh home-server`, працював і в домашній мережі (напряму), і поза домом (через VPS по зворотному тунелю). Потребує працюючого [зворотного тунелю](reverse-ssh-tunnel-systemd.md). `ProxyJump` (`-J`) змушує SSH-клієнт відкрити з'єднання з проміжним хостом і пустити справжнє з'єднання крізь нього.

## 1. Записи для підключення поза домом

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
    # Loopback-порт VPS має іншу ідентичність ключа хоста, ніж адреса в LAN
    HostKeyAlias <SERVER_HOSTNAME>
    ServerAliveInterval 30
```

Тут `127.0.0.1` розв'язується на VPS (останньому переході), де слухає тунель. Перевірка:

```bash
ssh home-server-remote
```

> **Попередження:** не використовуйте `ProxyJump` через VPS до LAN-адреси домашнього сервера (`<SERVER_IP>`): VPS не бачить домашню локальну мережу. Маршрут завжди такий: ноутбук -> VPS -> порт тунелю -> домашній сервер.

## 2. Один псевдонім для дому та поза домом

`ssh_config` використовує перше отримане значення кожної опції, тож умовний блок ставте перед загальним. `Match ... exec` виконує команду; якщо вона завершується успішно, блок застосовується.

```
# Доступний у LAN -> підключатися напряму
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

| Частина | Навіщо |
|---|---|
| `nc -z -G 1` | macOS: TCP-перевірка з тайм-аутом 1 с. У Linux використовуйте `-w 1` замість `-G 1` |
| `ProxyJump none` | Потрібне, щоб скасувати перехід, бо пізніший блок `Host` інакше додав би його |
| `HostKeyAlias` | Обидва шляхи пред'являють той самий ключ сервера під одним іменем, тому `known_hosts` залишається узгодженим і попереджень про ключ хоста немає |

Перевірка LAN додає до однієї секунди лише поза домом. Ім'я хоста й порт беруться з першого блоку, який їх задає.

## 3. IDE та інструменти

З псевдонімом працює будь-який інструмент, що читає `~/.ssh/config`: VS Code/Cursor Remote-SSH (`home-server` з'являється у списку хостів; див. [IDE Remote-SSH](../04-git-and-ide/ide-remote-ssh.md)), `scp`, `rsync`, `git` через SSH.

```bash
scp ./file.txt home-server:~/
rsync -av ./dist/ home-server:~/site/
```

Одноразово, без редагування конфігурації:

```bash
ssh -J <VPS_USER>@<VPS_IP>:<SSH_PORT> -p <TUNNEL_PORT> <SERVER_USER>@127.0.0.1
```

Для `kubectl` з ноутбука прокиньте порт API через той самий псевдонім:

```bash
ssh -N -L 6443:127.0.0.1:6443 home-server
```

## Перевірка

```bash
ssh -G home-server | grep -Ei '^(hostname|port|proxyjump) '
ssh home-server hostname
```

Вдома `-G` показує `<SERVER_IP>` і жодного proxyjump; поза домом — `127.0.0.1`, `<TUNNEL_PORT>` і `proxyjump vps-gateway`. Додайте `-v`, щоб побачити, якими переходами йде з'єднання.

| Симптом | Причина / виправлення |
|---|---|
| `Connection closed by UNKNOWN port 65535` | Тунель не працює; перевірте службу на домашньому сервері |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Немає `HostKeyAlias` або сервер було перевстановлено; `ssh-keygen -R <SERVER_HOSTNAME>` |
| Вдома завжди йде через VPS | LAN-перевірка не проходить (брандмауер, неправильний `<SERVER_IP>` або прапорець `nc` не для вашої ОС) |
| `Permission denied (publickey)` | Публічного ключа ноутбука немає в `authorized_keys` користувача `<SERVER_USER>` на домашньому сервері |

Далі: [Конвеєр GitLab CI](../07-cicd/gitlab-ci-petproject-pipeline.md)
