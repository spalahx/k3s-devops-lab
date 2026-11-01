# Укрепление SSH

Настраивает вход по SSH только по ключам для не-root пользователя с sudo и переносит SSH с порта 22 на `<SSH_PORT>`. Делайте это на любом сервере, доступном извне; для чисто локальной машины это тоже дёшево и полезно.

> **Warning:** чтобы не заблокировать себе доступ, держите одну рабочую SSH-сессию открытой всю процедуру и проверяйте каждое изменение из второго терминала. Если используете UFW, откройте `<SSH_PORT>` в нём **до** смены порта SSH ([Firewall](firewall-ufw.md), шаги 1–3).

## 1. Пользователь с sudo (не root)

Пропустите, если вы уже работаете под пользователем из установщика `<SERVER_USER>`. Чтобы добавить ещё одного администратора:

```bash
sudo adduser <SERVER_USER>
sudo usermod -aG sudo <SERVER_USER>      # -a обязателен: без него все остальные группы будут удалены
su - <SERVER_USER>
sudo whoami                              # должно вывести: root
```

## 2. Аутентификация по ключу с ноутбука

На ноутбуке (macOS или Linux), по одному ключу на сервер или назначение:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "<GIT_PERSONAL_EMAIL>" -f ~/.ssh/<SERVER_HOSTNAME>
```

- `ed25519` — современный короткий и быстрый тип ключа.
- Комментарий (`-C`) — просто метка. Задайте passphrase; на macOS добавьте `AddKeysToAgent yes` и `UseKeychain yes` в блок `Host` ниже, чтобы не вводить её каждый раз.
- `~/.ssh/<SERVER_HOSTNAME>` — приватный ключ, он не покидает ноутбук; `.pub` — публичный.

Скопируйте публичный ключ (один раз спросит пароль учётной записи):

```bash
ssh-copy-id -i ~/.ssh/<SERVER_HOSTNAME>.pub <SERVER_USER>@<SERVER_IP>
```

Если `ssh-copy-id` нет (редко на macOS):

```bash
cat ~/.ssh/<SERVER_HOSTNAME>.pub | ssh <SERVER_USER>@<SERVER_IP> 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Добавьте клиентский алиас в `~/.ssh/config` на ноутбуке (пока порт 22):

```
Host <SERVER_HOSTNAME>
    HostName <SERVER_IP>
    User <SERVER_USER>
    IdentityFile ~/.ssh/<SERVER_HOSTNAME>
    IdentitiesOnly yes
    Port 22
```

Проверьте и не продолжайте, пока вход не происходит **без пароля учётной записи**:

```bash
ssh <SERVER_HOSTNAME>
```

## 3. Укрепление `sshd`

Ubuntu читает drop-in файлы из `/etc/ssh/sshd_config.d/`, при этом побеждает первое значение, поэтому файл с префиксом `01-` переопределяет значения по умолчанию облачных образов (`50-cloud-init.conf` может задавать `PasswordAuthentication yes`).

> **Warning:** не записывайте эти строки вместо этого в основной `/etc/ssh/sshd_config`. `Include` для `sshd_config.d/*.conf` стоит выше них, поэтому `PasswordAuthentication yes` из `50-cloud-init.conf` всё равно побеждает, и вход по паролю остаётся включённым, хотя в основном файле написано `no`. Всегда проверяйте результат через `sudo sshd -T` (ниже).

```bash
sudo tee /etc/ssh/sshd_config.d/01-hardening.conf >/dev/null <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
CONF
sudo sshd -t && echo OK        # тишина или OK = синтаксис верен
sudo systemctl reload ssh
```

Откройте **новый** терминал и убедитесь, что `ssh <SERVER_HOSTNAME>` по-прежнему работает. Проверьте действующие значения:

```bash
sudo sshd -T | grep -E "^(passwordauthentication|permitrootlogin|pubkeyauthentication)"
```

## 4. Смена порта на `<SSH_PORT>`

Выберите свободный порт выше 1024 (например `2222`). Порядок действий:

1. Сначала разрешите его в фаерволе (если UFW активен): `sudo ufw allow <SSH_PORT>/tcp`.
2. Добавьте порт в `sshd`, **пока оставив 22**.
3. Проверьте новый порт из второго терминала.
4. Только потом уберите порт 22.

SSH в Ubuntu запускается через **socket activation**: `ssh.socket` владеет слушающим портом. Как выбирается порт, зависит от релиза:

- **Ubuntu 26.04 (проверено на эталонном сервере):** слушающие адреса генерируются из `sshd_config` (`/run/systemd/generator/ssh.socket.d/addresses.conf`, создаётся `sshd-socket-generator`), поэтому достаточно задать `Port`. Файл юнита `systemctl cat ssh.socket` по-прежнему показывает `ListenStream=22`; это ожидаемо, сгенерированный файл его переопределяет.
- **Ubuntu 22.10–24.04:** сокет может игнорировать `Port` из `sshd_config`; задайте порт на сокете через drop-in (см. «Старые релизы» ниже).

В 26.04 на время миграции оставьте оба порта:

```bash
sudo tee /etc/ssh/sshd_config.d/02-port.conf >/dev/null <<'CONF'
Port 22
Port <SSH_PORT>
CONF
sudo sshd -t && echo OK
sudo systemctl daemon-reload      # генератор перечитывает sshd_config
sudo systemctl restart ssh.socket
sudo ss -tlnp | grep -E "sshd|:22 |:<SSH_PORT> "
```

В выводе `ss` должны быть оба порта. Если виден только 22, сгенерированный сокет не обновился: повторите `daemon-reload` и перезапуск или используйте drop-in из раздела «Старые релизы».

**Старые релизы (22.10–24.04) и запасной вариант:**

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

- Пустая строка `ListenStream=` сбрасывает значение по умолчанию перед добавлением новых.
- Если используется классический сервис без сокета (`systemctl status ssh.socket` показывает `not-found`/`inactive`), достаточно строки `Port` в `sshd_config` или drop-in, затем `sudo systemctl restart ssh`.

Обновите алиас на ноутбуке (`Port <SSH_PORT>`) и проверьте из нового терминала:

```bash
ssh -p <SSH_PORT> <SERVER_USER>@<SERVER_IP>
```

Когда вход стабильно работает, уберите порт 22:

В 26.04 удалите строку `Port 22` из `/etc/ssh/sshd_config.d/02-port.conf`; при варианте с drop-in сокета вместо этого удалите `ListenStream=22` из `listen.conf`. Затем:

```bash
sudo sed -i '/^Port 22$/d' /etc/ssh/sshd_config.d/02-port.conf      # 26.04 (вариант с drop-in: правьте listen.conf)
sudo systemctl daemon-reload && sudo systemctl restart ssh.socket
sudo ufw delete allow 22/tcp          # если вы его открывали
```

## Verify

```bash
ssh <SERVER_HOSTNAME>                                  # вход по ключу на <SSH_PORT>
ssh -p 22 <SERVER_USER>@<SERVER_IP>                    # должно завершиться ошибкой (connection refused)
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password <SERVER_USER>@<SERVER_IP> -p <SSH_PORT>   # Permission denied
ssh root@<SERVER_IP> -p <SSH_PORT>                     # Permission denied
```

## Решение проблем

| Симптом | Решение |
|---|---|
| `Permission denied (publickey)` | На сервере: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`; через `ssh -v <SERVER_HOSTNAME>` проверьте, что предлагается нужный ключ; убедитесь, что копировали файл `.pub` |
| Смена порта не действует | `ss -tlnp` по-прежнему показывает только 22: повторите `daemon-reload` и `restart ssh.socket`; на релизах до 24.04 drop-in сокета обязателен |
| Вход по паролю всё ещё работает | Какой-то drop-in (например, `50-cloud-init.conf`) задаёт `PasswordAuthentication yes` раньше вашего значения; проверьте `sudo grep -ri passwordauth /etc/ssh/` и `sudo sshd -T` |
| Connection refused на новом порту | Порт не слушается (`ss -tlnp`) или заблокирован: `sudo ufw status`, `sudo journalctl -u ssh -n 50` |
| Потерян доступ | Нужна консоль: исправьте `/etc/ssh/sshd_config.d/*` и drop-in сокета, перезапустите `ssh.socket` |

Next: [Firewall (UFW)](firewall-ufw.md)
