# Fail2ban

Банит IP-адреса, которые многократно ошибаются при входе по SSH, добавляя временные правила фаервола. Дополняет вход только по ключам ([SSH hardening](ssh-hardening.md)); ставьте после перевода SSH на `<SSH_PORT>`.

## 1. Установка

```bash
sudo apt update && sudo apt install fail2ban -y
```

## 2. Настройка jail для sshd

Не правьте `jail.conf`: обновления пакета его перезаписывают. Настройки кладите в `jail.local` (или файл в `jail.d/`), он переопределяет `jail.conf`.

```bash
sudo tee /etc/fail2ban/jail.local >/dev/null <<'CONF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 3
backend  = systemd
ignoreip = 127.0.0.1/8 ::1 192.168.1.0/24

[sshd]
enabled = true
port    = <SSH_PORT>
CONF
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban
```

| Параметр | Значение |
|---|---|
| `maxretry` | Число неудачных попыток за `findtime` до бана |
| `findtime` | Окно, в котором считаются ошибки |
| `bantime` | Длительность бана (`-1` = навсегда; `bantime.increment = true` увеличивает срок для повторных нарушителей) |
| `ignoreip` | Никогда не банить: loopback и ваша LAN. Подставьте свою подсеть и добавьте свой постоянный публичный IP, если он есть |
| `backend = systemd` | Читать журнал systemd (работает, даже если `/var/log/auth.log` отсутствует) |

`port` должен совпадать с реальным портом SSH. С портом 22 по умолчанию jail будет читать лог, но банить не тот порт.

## 3. Управление

```bash
sudo fail2ban-client status                 # список jail
sudo fail2ban-client status sshd            # забаненные IP и счётчики
sudo fail2ban-client set sshd unbanip 203.0.113.50
sudo fail2ban-client set sshd banip 203.0.113.50
sudo tail -f /var/log/fail2ban.log
```

> **Warning:** проверка jail с собственного ноутбука неверными ключами забанит ваш IP (если его нет в `ignoreip`). Разбаньте с консоли или с другого канала.

## 4. Автоматические обновления безопасности

`unattended-upgrades` ставит патчи безопасности без ручной работы. На Ubuntu Server обычно уже установлен:

```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades     # ответьте Yes
```

Настройки: `/etc/apt/apt.conf.d/50unattended-upgrades` (источник security включён по умолчанию). Автоперезагрузка по умолчанию выключена; включайте, только если приемлем короткий простой в заданное время:

```
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
```

На узле K3s перезагрузка перезапускает все поды, поэтому вариант по умолчанию (без автоперезагрузки, ручная перезагрузка после обновления ядра) обычно лучше.

## Verify

```bash
sudo fail2ban-client status sshd
```

В выводе должны быть `Journal matches: _SYSTEMD_UNIT=ssh.service + _COMM=sshd` (или `sshd.service`) и `Currently banned: 0`. Проверка: с устройства, которого нет в `ignoreip`, трижды неудачно войдите с неверным ключом/пользователем, затем `status sshd` покажет этот IP. Проверка обновлений:

```bash
sudo unattended-upgrade --dry-run --debug | tail -5
systemctl status unattended-upgrades --no-pager | head -5
```

## Решение проблем

| Симптом | Решение |
|---|---|
| Неудачные входы видны, банов нет | Несовпадение `port`; неверный `backend`; смотрите `/var/log/fail2ban.log` |
| `Journal matches` пусто | Нет `backend = systemd` или имя unit SSH другое: `systemctl list-units | grep ssh` |
| Забанили себя | `sudo fail2ban-client set sshd unbanip <IP>` из консоли или другой сети |

Next: [Docker install](../03-containers-and-k3s/docker-install.md)
