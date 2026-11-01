# Захист SSH

Налаштовує вхід через SSH лише за ключем для не-root користувача з sudo і переносить SSH з порту 22 на `<SSH_PORT>`. Робіть це на кожному сервері, доступному ззовні його власної кімнати; для суто локальної машини це також недорого і є доброю звичкою.

> **Попередження:** щоб не заблокувати собі доступ, тримайте одну робочу SSH-сесію відкритою протягом усієї процедури і перевіряйте кожну зміну з другого термінала. Якщо ви використовуєте UFW, відкрийте в ньому `<SSH_PORT>` **до** перемикання порту SSH ([Брандмауер](firewall-ufw.md), кроки 1-3).

## 1. Не-root користувач із sudo

Пропустіть, якщо користувач інсталятора `<SERVER_USER>` уже є тим, під яким ви працюєте. Щоб додати іншого адміністратора:

```bash
sudo adduser <SERVER_USER>
sudo usermod -aG sudo <SERVER_USER>      # -a обов'язковий: без нього всі інші групи буде видалено
su - <SERVER_USER>
sudo whoami                              # має вивести: root
```

## 2. Автентифікація за ключем з ноутбука

На ноутбуці (macOS або Linux), по одному ключу на сервер або на призначення:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "<GIT_PERSONAL_EMAIL>" -f ~/.ssh/<SERVER_HOSTNAME>
```

- `ed25519` це сучасний, короткий і швидкий тип ключа.
- Коментар (`-C`) лише мітка. Задайте парольну фразу; на macOS додайте `AddKeysToAgent yes` і `UseKeychain yes` у блок `Host` нижче, щоб не вводити її повторно.
- `~/.ssh/<SERVER_HOSTNAME>` є приватним і ніколи не залишає ноутбук; `.pub` є публічним.

Скопіюйте публічний ключ (один раз запитає пароль облікового запису):

```bash
ssh-copy-id -i ~/.ssh/<SERVER_HOSTNAME>.pub <SERVER_USER>@<SERVER_IP>
```

Якщо `ssh-copy-id` відсутній (рідко на macOS), використайте:

```bash
cat ~/.ssh/<SERVER_HOSTNAME>.pub | ssh <SERVER_USER>@<SERVER_IP> 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Додайте клієнтський аліас у `~/.ssh/config` на ноутбуці (порт поки що 22):

```
Host <SERVER_HOSTNAME>
    HostName <SERVER_IP>
    User <SERVER_USER>
    IdentityFile ~/.ssh/<SERVER_HOSTNAME>
    IdentitiesOnly yes
    Port 22
```

Перевірте і не продовжуйте, доки вхід не відбувається **без пароля облікового запису**:

```bash
ssh <SERVER_HOSTNAME>
```

## 3. Захист `sshd`

Ubuntu читає drop-in файли з `/etc/ssh/sshd_config.d/`, і перемагає перше значення, тому drop-in з префіксом `01-` перевизначає типові значення хмарних образів (`50-cloud-init.conf` може задавати `PasswordAuthentication yes`).

> **Попередження:** не записуйте ці рядки натомість в основний `/etc/ssh/sshd_config`. `Include` для `sshd_config.d/*.conf` стоїть вище за них, тому `PasswordAuthentication yes` з `50-cloud-init.conf` усе одно перемагає, і вхід за паролем лишається ввімкненим, хоча в основному файлі написано `no`. Завжди перевіряйте результат через `sudo sshd -T` (нижче).

```bash
sudo tee /etc/ssh/sshd_config.d/01-hardening.conf >/dev/null <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
CONF
sudo sshd -t && echo OK        # тиша або OK = синтаксис коректний
sudo systemctl reload ssh
```

Відкрийте **новий** термінал і переконайтеся, що `ssh <SERVER_HOSTNAME>` досі працює. Перевірте чинні значення:

```bash
sudo sshd -T | grep -E "^(passwordauthentication|permitrootlogin|pubkeyauthentication)"
```

## 4. Зміна порту на `<SSH_PORT>`

Виберіть вільний порт вище 1024 (наприклад, `2222`). Застосовуйте в такому порядку:

1. Спершу дозвольте його в брандмауері (якщо UFW активний): `sudo ufw allow <SSH_PORT>/tcp`.
2. Додайте порт у `sshd`, **поки що залишивши 22**.
3. Перевірте новий порт з другого термінала.
4. Лише після цього видаліть порт 22.

SSH в Ubuntu запускається через **socket activation**: `ssh.socket` володіє портом, що слухається. Як обирається порт, залежить від релізу:

- **Ubuntu 26.04 (перевірено на еталонному сервері):** адреси, що слухаються, генеруються з `sshd_config` (`/run/systemd/generator/ssh.socket.d/addresses.conf`, створює `sshd-socket-generator`), тому достатньо задати `Port`. Файл юніта `systemctl cat ssh.socket` досі показує `ListenStream=22`; це очікувано, згенерований файл його перевизначає.
- **Ubuntu 22.10–24.04:** сокет може ігнорувати `Port` з `sshd_config`; задайте порт на сокеті через drop-in (див. «Старі релізи» нижче).

У 26.04 на час міграції залиште обидва порти:

```bash
sudo tee /etc/ssh/sshd_config.d/02-port.conf >/dev/null <<'CONF'
Port 22
Port <SSH_PORT>
CONF
sudo sshd -t && echo OK
sudo systemctl daemon-reload      # генератор перечитує sshd_config
sudo systemctl restart ssh.socket
sudo ss -tlnp | grep -E "sshd|:22 |:<SSH_PORT> "
```

У виводі `ss` мають бути обидва порти. Якщо видно лише 22, згенерований сокет не оновився: повторіть `daemon-reload` і перезапуск або скористайтеся drop-in із розділу «Старі релізи».

**Старі релізи (22.10–24.04) і запасний варіант:**

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

- Порожній рядок `ListenStream=` очищає значення за замовчуванням перед додаванням нових.
- Якщо система використовує класичний сервіс без сокета (`systemctl status ssh.socket` повідомляє `not-found`/`inactive`), потрібен лише рядок `Port` у `sshd_config` або його drop-in, після чого `sudo systemctl restart ssh`.

Змініть аліас на ноутбуці (`Port <SSH_PORT>`) і перевірте з нового термінала:

```bash
ssh -p <SSH_PORT> <SERVER_USER>@<SERVER_IP>
```

Коли це стабільно працює, приберіть порт 22:

У 26.04 видаліть рядок `Port 22` з `/etc/ssh/sshd_config.d/02-port.conf`; у варіанті з drop-in сокета натомість видаліть `ListenStream=22` з `listen.conf`. Потім:

```bash
sudo sed -i '/^Port 22$/d' /etc/ssh/sshd_config.d/02-port.conf      # 26.04 (варіант з drop-in: редагуйте listen.conf)
sudo systemctl daemon-reload && sudo systemctl restart ssh.socket
sudo ufw delete allow 22/tcp          # якщо ви його відкривали
```

## Перевірка

```bash
ssh <SERVER_HOSTNAME>                                  # вхід за ключем на <SSH_PORT>
ssh -p 22 <SERVER_USER>@<SERVER_IP>                    # має завершитися помилкою (connection refused)
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password <SERVER_USER>@<SERVER_IP> -p <SSH_PORT>   # Permission denied
ssh root@<SERVER_IP> -p <SSH_PORT>                     # Permission denied
```

## Усунення проблем

| Симптом | Виправлення |
|---|---|
| `Permission denied (publickey)` | На сервері: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`; через `ssh -v <SERVER_HOSTNAME>` перевірте, що пропонується правильний ключ; переконайтеся, що ви скопіювали файл `.pub` |
| Зміна порту не діє | `ss -tlnp` досі показує лише 22: повторіть `daemon-reload` і `restart ssh.socket`; на релізах до 24.04 drop-in сокета обов'язковий |
| Вхід за паролем досі працює | Якийсь drop-in (наприклад, `50-cloud-init.conf`) задає `PasswordAuthentication yes` раніше за ваше значення; перевірте `sudo grep -ri passwordauth /etc/ssh/` і `sudo sshd -T` |
| Connection refused на новому порту | Не слухається (`ss -tlnp`) або заблоковано: `sudo ufw status`, `sudo journalctl -u ssh -n 50` |
| Доступ заблоковано | Потрібен доступ до консолі: виправте `/etc/ssh/sshd_config.d/*` і drop-in сокета, перезапустіть `ssh.socket` |

Далі: [Брандмауер (UFW)](firewall-ufw.md)
