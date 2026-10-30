# Налаштування VPS-шлюзу

Підготовка невеликого орендованого VPS зі статичною публічною IP-адресою, який виступає точкою зустрічі для домашнього сервера за NAT або з динамічною IP-адресою. Пропустіть цей крок, якщо сервер уже має публічну статичну IP-адресу (наприклад, хмарний VPS) або якщо ви віддаєте перевагу VPN, як-от WireGuard/Tailscale.

Як це працює: домашній сервер відкриває вихідне SSH-з'єднання до VPS і публікує свій SSH-порт на VPS (`ssh -R`). Клієнти підключаються до VPS, який пересилає трафік назад через це з'єднання. Прокидання портів на роутері не потрібне, а домашня IP-адреса може змінюватися.

Плейсхолдери, що використовуються тут (на додачу до стандартних):

| Плейсхолдер | Значення |
|---|---|
| `<VPS_USER>` | Адміністративний користувач на VPS (не root, з sudo) |
| `<TUNNEL_USER>` | Непривілейований користувач на VPS, який лише утримує тунель |
| `<TUNNEL_PORT>` | Порт на loopback VPS, що відображається на SSH домашнього сервера (наприклад, `2222`) |

## 1. Оренда VPS

- Підійде будь-який провайдер; найменшого тарифу (1 vCPU / 1 ГБ RAM) достатньо, адже він лише ретранслює SSH.
- Оберіть ту саму Ubuntu Server LTS, що й на домашньому сервері.
- Запишіть публічну IP-адресу (`<VPS_IP>`) і початкові дані для входу.

## 2. Створення адміністративного користувача та захист

```bash
ssh root@<VPS_IP>
adduser <VPS_USER>
usermod -aG sudo <VPS_USER>
```

З ноутбука встановіть ключ і перевірте вхід, перш ніж змінювати щось інше:

```bash
ssh-copy-id <VPS_USER>@<VPS_IP>
ssh <VPS_USER>@<VPS_IP>
```

Потім застосуйте ту саму базову конфігурацію, що й на домашньому сервері: [захист SSH](../02-security/ssh-hardening.md), [UFW](../02-security/firewall-ufw.md), [Fail2ban](../02-security/fail2ban.md). VPS напряму доступний з інтернету, тож це обов'язково. Відкрийте лише порт SSH:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow <SSH_PORT>/tcp
sudo ufw enable
```

> **Попередження:** тримайте відкритою другу сесію, поки змінюєте налаштування SSH або правила брандмауера, і дозвольте порт SSH до ввімкнення UFW.

## 3. Створення користувача для тунелю

Окремий користувач обмежує збитки, якщо домашній сервер (або його ключ) буде скомпрометовано.

```bash
sudo adduser --disabled-password --gecos "" --shell /usr/sbin/nologin <TUNNEL_USER>
sudo install -d -m 700 -o <TUNNEL_USER> -g <TUNNEL_USER> /home/<TUNNEL_USER>/.ssh
```

Оболонка `nologin` підходить: `ssh -N -R` не потребує оболонки.

## 4. Створення ключа тунелю на домашньому сервері

Окремий ключ, не той, що використовується для Git:

```bash
ssh-keygen -t ed25519 -C "home-to-vps-tunnel" -f ~/.ssh/id_ed25519_tunnel -N ""
cat ~/.ssh/id_ed25519_tunnel.pub
```

Парольну фразу не задано, бо служба systemd має стартувати без участі людини. Компенсуйте це обмеженням ключа на стороні VPS.

На VPS додайте публічний ключ до `/home/<TUNNEL_USER>/.ssh/authorized_keys` одним рядком з обмеженнями:

```
restrict,port-forwarding,permitlisten="127.0.0.1:<TUNNEL_PORT>" ssh-ed25519 AAAA...key... home-to-vps-tunnel
```

```bash
sudo chown <TUNNEL_USER>:<TUNNEL_USER> /home/<TUNNEL_USER>/.ssh/authorized_keys
sudo chmod 600 /home/<TUNNEL_USER>/.ssh/authorized_keys
```

| Опція | Дія |
|---|---|
| `restrict` | Вимикає PTY, перенаправлення agent/X11 і виконання команд |
| `port-forwarding` | Знову вмикає лише перенаправлення портів |
| `permitlisten` | Ключ може відкрити на VPS лише цей єдиний listener |

## 5. Налаштування sshd на VPS

Перевірте чинні значення:

```bash
sudo sshd -T | grep -Ei 'allowtcpforwarding|gatewayports'
```

| Налаштування | Значення | Коли |
|---|---|---|
| `AllowTcpForwarding` | `yes` (за замовчуванням) | Потрібне для `-R` |
| `GatewayPorts` | `no` (за замовчуванням) | Рекомендовано. Порт тунелю слухає лише на `127.0.0.1` VPS, а клієнти досягають його через [ProxyJump](proxyjump-client-config.md) |
| `GatewayPorts` | `clientspecified` або `yes` | Лише якщо треті сторони мають підключатися напряму до `<VPS_IP>:<TUNNEL_PORT>` |

Якщо справді потрібен прямий зовнішній доступ, змініть `/etc/ssh/sshd_config` (або файл у `/etc/ssh/sshd_config.d/`):

```
GatewayPorts clientspecified
```

```bash
sudo sshd -t && sudo systemctl restart ssh
```

З `clientspecified` сторона тунелю має використовувати `-R 0.0.0.0:<TUNNEL_PORT>:localhost:<SSH_PORT>`, а значення `permitlisten` в `authorized_keys` має збігатися з цією адресою. Потім обмежте порт у UFW:

```bash
sudo ufw allow from 203.0.113.50 to any port <TUNNEL_PORT> proto tcp
```

> **Попередження:** публічно доступний порт тунелю відкриває SSH домашнього сервера для спроб підбору паролів. Вимагайте вхід лише за ключем на домашньому сервері та обмежте вихідні IP-адреси в UFW.

## Перевірка

```bash
# З домашнього сервера: вхід за ключем працює (у користувача тунелю немає оболонки, тож очікуйте закриту сесію)
ssh -i ~/.ssh/id_ed25519_tunnel <TUNNEL_USER>@<VPS_IP> -p <SSH_PORT>
# На VPS: конфігурація sshd коректна, а брандмауер активний
sudo sshd -t && sudo ufw status
```

Далі: [Зворотний SSH-тунель як служба systemd](reverse-ssh-tunnel-systemd.md)
