# Статична IP-адреса та мережа

Надає серверу стабільну адресу, ім'я хоста й правильний годинник, а також забезпечує розв'язання імен `*.<DOMAIN_BASE>` на ноутбуці. Змінна IP-адреса ламає SSH-аліаси, записи hosts і кожен сервіс, що вказує на сервер, тому зробіть це до того, як на цьому буде збудовано щось інше.

## 1. Визначення інтерфейсу

```bash
ip -br a            # назва інтерфейсу та поточна адреса
ip route | grep default   # адреса шлюзу (роутера)
resolvectl status | grep -A2 "Link"   # поточні DNS-сервери
```

Приклади значень нижче: інтерфейс `enp1s0`, сервер `192.168.1.150`, роутер `192.168.1.1`. Підставте свої (`<SERVER_IP>` це адреса, яку ви обираєте).

## 2. Варіант A: DHCP-резервування на роутері (найпростіше)

На сторінці адміністрування роутера (розділ DHCP / LAN) прив'яжіть MAC-адресу сервера до потрібної IP-адреси. MAC-адресу показує команда:

```bash
ip link show enp1s0 | grep link/ether
```

На сервері нічого не змінюється. Назви цієї функції різняться: DHCP reservation, static DHCP, address reservation. Перезавантажте сервер (або оновіть оренду), щоб отримати адресу.

## 3. Варіант B: статична IP-адреса через netplan

Netplan це рівень мережевої конфігурації Ubuntu (YAML-файли в `/etc/netplan/`). Виберіть адресу поза діапазоном DHCP роутера.

```bash
ls /etc/netplan/
sudo cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak
sudo nano /etc/netplan/50-cloud-init.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: false
      addresses:
        - <SERVER_IP>/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

- Відступи лише пробілами, по 2 на рівень. Табуляція або неправильний відступ роблять файл недійсним.
- `routes: to: default` замінює застарілий `gateway4`.
- Файли netplan не повинні бути доступними для читання всім: `sudo chmod 600 /etc/netplan/*.yaml`.
- Назва файлу може відрізнятися (`00-installer-config.yaml`); редагуйте той, що існує.

Застосуйте з автоматичним відкатом, щоб помилка не заблокувала вам доступ:

```bash
sudo netplan try        # натисніть Enter протягом 120 с, щоб залишити, інакше буде відкат
sudo netplan apply
```

> **Попередження:** запускайте `netplan try` з консолі або з SSH-сесії, яку не шкода втратити. Якщо ви змінили IP, поточна SSH-сесія обірветься; підключіться знову до нової адреси.

## 4. Ім'я хоста та часовий пояс

```bash
sudo hostnamectl set-hostname <SERVER_HOSTNAME>
sudo timedatectl set-timezone Europe/Berlin     # використайте свій пояс: timedatectl list-timezones
timedatectl set-ntp true
```

Якщо в `/etc/hosts` є рядок `127.0.1.1` зі старим ім'ям хоста, змініть його на `<SERVER_HOSTNAME>`.

## 5. Розв'язання імен на сервері

```bash
resolvectl query ubuntu.com
ping -c2 1.1.1.1 && ping -c2 ubuntu.com
```

Якщо IP відповідає, а ім'я ні, DNS не працює: перевірте ще раз `nameservers` у файлі netplan.

## 6. Розв'язання `*.<DOMAIN_BASE>` на ноутбуці

Проєкти доступні за іменами хостів на кшталт `<PROJECT_NAME>.<DOMAIN_BASE>`, які Traefik маршрутизує за заголовком `Host`. У приватній LAN публічного DNS-запису немає, тому ноутбук має зіставити імена з `<SERVER_IP>`.

| Метод | Коли | Як |
|---|---|---|
| Файл `hosts` | Кілька проєктів, один ноутбук | Один рядок на ім'я, нижче |
| Локальний DNS (роутер або `dnsmasq`) | Багато імен або багато пристроїв | Wildcard `address=/<DOMAIN_BASE>/<SERVER_IP>` |
| Публічний DNS A-запис | Хмарний сервер із публічною IP | Див. [Відмінності локального та хмарного середовища](../00-overview/local-vs-cloud-differences.md) |

Розташування файлу `hosts`: macOS/Linux `/etc/hosts` (редагуйте через `sudo`).

```bash
echo "<SERVER_IP>  <PROJECT_NAME>.<DOMAIN_BASE> phpmyadmin.<PROJECT_NAME>.<DOMAIN_BASE>" | sudo tee -a /etc/hosts
# лише macOS: скинути DNS-кеш
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

- Формат суворий: IP, потім імена через пробіли, в одному рядку. Без `http://`, без кінцевого слеша.
- Файл `hosts` не підтримує wildcard; кожне ім'я потрібно перелічити.
- Уникайте суфікса `.local` для `<DOMAIN_BASE>` на macOS/Linux: він зарезервований для mDNS і може розв'язуватися повільно або взагалі не розв'язуватися. Краще щось на кшталт `.lab` або `.home.arpa`.

Локальний wildcard DNS через `dnsmasq` (на сервері або на будь-якому хості LAN, що працює постійно), якщо ви віддаєте перевагу йому замість `hosts`:

```bash
sudo apt install dnsmasq -y
echo "address=/<DOMAIN_BASE>/<SERVER_IP>" | sudo tee /etc/dnsmasq.d/lab.conf
sudo systemctl restart dnsmasq
```

Потім вкажіть цей хост як DNS-сервер на роутері або ноутбуці. На машині з `systemd-resolved` (стандарт для Ubuntu) порт 53 зайнятий stub-резолвером; спершу задайте `DNSStubListener=no` у `/etc/systemd/resolved.conf` або запустіть dnsmasq на іншому хості.

## Wi-Fi

Використовуйте Ethernet для вузла K3s. Перевірки стану Kubernetes сприймають коротку затримку Wi-Fi як відмову вузла, і Pod перезапускаються випадково. Для деяких Wi-Fi-чипів узагалі немає драйвера в mainline. Якщо Wi-Fi єдиний варіант або чип не виявлено, див. [Усунення проблем із мережею](../99-appendix/troubleshooting-networking.md); надійний запасний варіант це USB Wi-Fi-адаптер із чипсетом, що давно підтримується.

## Перевірка

```bash
ip -br a                       # <SERVER_IP> на інтерфейсі
ip route | grep default
hostnamectl                    # ім'я хоста, часовий пояс через: timedatectl
ping -c2 ubuntu.com
```

З ноутбука:

```bash
ping -c2 <SERVER_IP>
ping -c2 <PROJECT_NAME>.<DOMAIN_BASE>     # розв'язується в <SERVER_IP>
ssh <SERVER_USER>@<SERVER_IP>
```

Один раз перезавантажте (`sudo reboot`) і переконайтеся, що адреса лишається тією самою.

Далі: [Захист SSH](../02-security/ssh-hardening.md)
