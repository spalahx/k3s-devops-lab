# Зворотний SSH-тунель як служба systemd

Підтримує постійне вихідне SSH-з'єднання від домашнього сервера до VPS, публікуючи домашній SSH-порт як `127.0.0.1:<TUNNEL_PORT>` на VPS. Потребує [VPS-шлюзу](vps-gateway-setup.md) з користувачем і ключем тунелю.

## 1. Ручна перевірка

Виконайте на домашньому сервері:

```bash
ssh -N -R 127.0.0.1:<TUNNEL_PORT>:localhost:<SSH_PORT> \
    -i ~/.ssh/id_ed25519_tunnel \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -p <SSH_PORT> <TUNNEL_USER>@<VPS_IP>
```

| Прапорець | Значення |
|---|---|
| `-N` | Без віддаленої команди; лише утримувати перенаправлення |
| `-R 127.0.0.1:<TUNNEL_PORT>:localhost:<SSH_PORT>` | Слухати на loopback VPS на `<TUNNEL_PORT>`, пересилати на власний SSH-порт домашнього сервера |
| `ExitOnForwardFailure=yes` | Завершитися, якщо порт не вдалося зайняти, щоб systemd перезапустив процес, а не залишав мертвий тунель |
| `ServerAliveInterval=30`, `ServerAliveCountMax=3` | Перевіряти кожні 30 с, розірвати після 3 пропусків (близько 90 с), щоб напівмертве з'єднання було виявлено й відновлено |

На VPS переконайтеся, що listener існує:

```bash
ss -tlnp | grep <TUNNEL_PORT>
```

Зупиніть тест за допомогою `Ctrl+C`, перш ніж створювати службу.

> **Попередження:** правильна назва опції — `ServerAliveCountMax`. Опції `ServerAliveCountAlive` не існує, і ssh її відхиляє.

## 2. Створення unit-файлу systemd

Достатньо звичайного `ssh` із keepalive. `autossh` — альтернативна обгортка, але разом з `ExitOnForwardFailure` і `Restart=always` вона нічого не додає.

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

`StrictHostKeyChecking=accept-new` записує ключ хоста VPS під час першого підключення без запиту (служба не може відповісти на запит). Щоб не довіряти йому наосліп, спершу один раз підключіться вручну як `<SERVER_USER>` і перевірте відбиток.

## 3. Увімкнення та запуск

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now vps-reverse-tunnel.service
```

## 4. Статус і журнали

```bash
systemctl status vps-reverse-tunnel.service
journalctl -u vps-reverse-tunnel.service -f
```

## Поведінка при перепідключенні

| Подія | Результат |
|---|---|
| Змінилася домашня IP-адреса / пропав Wi-Fi | Keepalive не проходить протягом ~90 с, ssh завершується, systemd перезапускає його після `RestartSec` |
| Перезавантаження сервера | Unit увімкнено, і він стартує після `network-online.target` |
| Перезавантаження VPS | ssh завершується, systemd повторює спробу кожні 10 с, доки VPS не повернеться |
| VPS досі утримує стару сесію | Нова спроба завершується помилкою `remote port forwarding failed`; з `ExitOnForwardFailure` процес завершується й повторює спроби, доки VPS не скине застарілу сесію. Якщо вона так і не зникає, задайте `ClientAliveInterval 30` і `ClientAliveCountMax 3` у `sshd_config` на VPS |

## Перевірка

На VPS:

```bash
ss -tlnp | grep <TUNNEL_PORT>
ssh -p <TUNNEL_PORT> <SERVER_USER>@127.0.0.1
```

Друга команда має привести в оболонку домашнього сервера (перевірте за допомогою `hostname`). Після цього налаштуйте клієнтську сторону.

Типові помилки:

| Повідомлення | Причина / виправлення |
|---|---|
| `remote port forwarding failed for listen port` | Порт зайнятий на VPS (застаріла сесія або інший процес) або `permitlisten` в `authorized_keys` не збігається з адресою `-R` |
| `Permission denied (publickey)` на VPS | Неправильний ключ або права на `authorized_keys` / `.ssh` користувача `<TUNNEL_USER>` |
| `Permission denied (publickey)` на `127.0.0.1:<TUNNEL_PORT>` | Публічного ключа користувача, що підключається, немає в `authorized_keys` домашнього користувача |
| Unit постійно перезапускається | Перегляньте `journalctl -u vps-reverse-tunnel`; зазвичай VPS недоступний або порт зайнятий |

Далі: [Клієнтська конфігурація ProxyJump](proxyjump-client-config.md)
