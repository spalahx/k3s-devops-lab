# Reverse SSH tunnel как служба systemd

Поддерживает постоянное исходящее SSH-соединение с домашнего сервера на VPS и публикует домашний SSH-порт как `127.0.0.1:<TUNNEL_PORT>` на VPS. Требуется [VPS-шлюз](vps-gateway-setup.md) с пользователем и ключом туннеля.

## 1. Проверить вручную

Выполняется на домашнем сервере:

```bash
ssh -N -R 127.0.0.1:<TUNNEL_PORT>:localhost:<SSH_PORT> \
    -i ~/.ssh/id_ed25519_tunnel \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -p <SSH_PORT> <TUNNEL_USER>@<VPS_IP>
```

| Флаг | Значение |
|---|---|
| `-N` | Без удалённой команды, только держать forwarding |
| `-R 127.0.0.1:<TUNNEL_PORT>:localhost:<SSH_PORT>` | Слушать на loopback VPS порт `<TUNNEL_PORT>` и пересылать на SSH-порт самого домашнего сервера |
| `ExitOnForwardFailure=yes` | Завершиться, если порт не удалось занять, — systemd перезапустит процесс вместо «мёртвого» туннеля |
| `ServerAliveInterval=30`, `ServerAliveCountMax=3` | Проверка каждые 30 с, обрыв после 3 пропусков (около 90 с): полумёртвое соединение обнаруживается и поднимается заново |

На VPS убедитесь, что listener появился:

```bash
ss -tlnp | grep <TUNNEL_PORT>
```

Остановите тест через `Ctrl+C` перед созданием службы.

> **Warning:** опция называется `ServerAliveCountMax`. Опции `ServerAliveCountAlive` не существует, ssh её отвергнет.

## 2. Создать unit systemd

Достаточно обычного `ssh` с keepalive. `autossh` — альтернативная обёртка, но вместе с `ExitOnForwardFailure` и `Restart=always` она ничего не добавляет.

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

`StrictHostKeyChecking=accept-new` запоминает host key VPS при первом подключении без вопроса (служба не может ответить на вопрос). Чтобы не доверять вслепую, сначала один раз подключитесь вручную от `<SERVER_USER>` и сверьте fingerprint.

## 3. Включить и запустить

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now vps-reverse-tunnel.service
```

## 4. Статус и логи

```bash
systemctl status vps-reverse-tunnel.service
journalctl -u vps-reverse-tunnel.service -f
```

## Поведение при переподключении

| Событие | Результат |
|---|---|
| Сменился домашний IP / пропал Wi-Fi | Keepalive срабатывает за ~90 с, ssh завершается, systemd перезапускает его через `RestartSec` |
| Перезагрузка сервера | Unit включён и стартует после `network-online.target` |
| Перезагрузка VPS | ssh завершается, systemd пробует каждые 10 с, пока VPS не вернётся |
| VPS ещё держит старую сессию | Новая попытка падает с `remote port forwarding failed`; с `ExitOnForwardFailure` процесс завершается и повторяет попытки, пока VPS не сбросит старую сессию. Если не проходит — задайте в `sshd_config` на VPS `ClientAliveInterval 30` и `ClientAliveCountMax 3` |

## Verify

На VPS:

```bash
ss -tlnp | grep <TUNNEL_PORT>
ssh -p <TUNNEL_PORT> <SERVER_USER>@127.0.0.1
```

Вторая команда должна открыть shell домашнего сервера (проверьте через `hostname`). После этого настройте клиентскую сторону.

Типичные ошибки:

| Сообщение | Причина / решение |
|---|---|
| `remote port forwarding failed for listen port` | Порт занят на VPS (старая сессия или другой процесс), либо `permitlisten` в `authorized_keys` не совпадает с адресом в `-R` |
| `Permission denied (publickey)` при входе на VPS | Неверный ключ или права на `authorized_keys` / `.ssh` у `<TUNNEL_USER>` |
| `Permission denied (publickey)` на `127.0.0.1:<TUNNEL_PORT>` | Публичного ключа подключающегося нет в `authorized_keys` домашнего пользователя |
| Unit бесконечно перезапускается | Смотрите `journalctl -u vps-reverse-tunnel`; обычно VPS недоступен или порт занят |

Next: [Клиентская конфигурация ProxyJump](proxyjump-client-config.md)
