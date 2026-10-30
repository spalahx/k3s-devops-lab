# Fail2ban

Банить IP-адреси, з яких повторно невдало входять через SSH, додаючи тимчасові правила брандмауера. Доповнює вхід лише за ключем ([Захист SSH](ssh-hardening.md)); встановлюйте після того, як SSH використовує `<SSH_PORT>`.

## 1. Встановлення

```bash
sudo apt update && sudo apt install fail2ban -y
```

## 2. Налаштування jail для sshd

Не редагуйте `jail.conf`: оновлення пакета його перезаписують. Розміщуйте налаштування в `jail.local` (або у файлі в `jail.d/`), який перевизначає `jail.conf`.

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

| Параметр | Значення |
|---|---|
| `maxretry` | Кількість невдалих спроб за `findtime` до бану |
| `findtime` | Вікно, в якому враховуються невдачі |
| `bantime` | Тривалість бану (`-1` = назавжди; `bantime.increment = true` змушує порушників, що повторюються, чекати довше) |
| `ignoreip` | Ніколи не банити: loopback і ваша LAN. Підлаштуйте підмережу та додайте власну фіксовану публічну IP-адресу, якщо вона є |
| `backend = systemd` | Читати журнал systemd (працює, навіть коли `/var/log/auth.log` відсутній) |

`port` має збігатися з реальним портом SSH. Зі стандартним 22 jail спостерігав би за журналом, але банив би не той порт.

## 3. Експлуатація

```bash
sudo fail2ban-client status                 # список jail
sudo fail2ban-client status sshd            # заблоковані IP та лічильники
sudo fail2ban-client set sshd unbanip 203.0.113.50
sudo fail2ban-client set sshd banip 203.0.113.50
sudo tail -f /var/log/fail2ban.log
```

> **Попередження:** перевірка jail зі свого ноутбука з неправильними ключами заблокує вашу ж IP-адресу (якщо її немає в `ignoreip`). Розблокуйте її іншим шляхом або з консолі.

## 4. Автоматичні оновлення безпеки

`unattended-upgrades` встановлює патчі безпеки без ручної роботи. Зазвичай він попередньо встановлений в Ubuntu Server:

```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades     # відповідайте Yes
```

Налаштування розташовані в `/etc/apt/apt.conf.d/50unattended-upgrades` (джерело security увімкнено за замовчуванням). Автоматичне перезавантаження вимкнено за замовчуванням; вмикайте його, лише якщо прийнятний короткий простій у визначений час:

```
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
```

На вузлі K3s перезавантаження перезапускає всі Pod, тому типовий варіант (без автоперезавантаження, ручне перезавантаження після оновлень ядра) зазвичай кращий.

## Перевірка

```bash
sudo fail2ban-client status sshd
```

Очікуваний вивід містить `Journal matches: _SYSTEMD_UNIT=ssh.service + _COMM=sshd` (або `sshd.service`) і `Currently banned: 0`. Симуляція: з пристрою, якого немає в `ignoreip`, тричі невдало увійдіть із неправильним ключем/користувачем, після чого `status sshd` покаже цю IP-адресу. Перевірка оновлень:

```bash
sudo unattended-upgrade --dry-run --debug | tail -5
systemctl status unattended-upgrades --no-pager | head -5
```

## Усунення проблем

| Симптом | Виправлення |
|---|---|
| Невдалі входи видно, але банів немає | Невідповідність `port`; неправильний `backend`; прочитайте `/var/log/fail2ban.log` |
| `Journal matches` порожній | Відсутній `backend = systemd`, або назва юніта SSH відрізняється: `systemctl list-units | grep ssh` |
| Забанили себе | `sudo fail2ban-client set sshd unbanip <IP>` з консолі або з іншої мережі |

Далі: [Встановлення Docker](../03-containers-and-k3s/docker-install.md)
