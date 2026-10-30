# Статический IP и сеть

Задаёт серверу постоянный адрес, имя хоста и правильное время и делает так, чтобы имена `*.<DOMAIN_BASE>` разрешались на ноутбуке. Меняющийся IP ломает SSH-алиасы, записи hosts и все сервисы, указывающие на сервер, поэтому сделайте это до всего остального.

## 1. Определение интерфейса

```bash
ip -br a                       # имя интерфейса и текущий адрес
ip route | grep default        # адрес шлюза (роутера)
resolvectl status | grep -A2 "Link"   # текущие DNS-серверы
```

Примеры значений ниже: интерфейс `enp1s0`, сервер `192.168.1.150`, роутер `192.168.1.1`. Подставьте свои (`<SERVER_IP>` — выбранный вами адрес).

## 2. Вариант A: резервирование DHCP на роутере (проще всего)

В админке роутера (раздел DHCP / LAN) привяжите MAC-адрес сервера к нужному IP. MAC показывает:

```bash
ip link show enp1s0 | grep link/ether
```

На сервере ничего менять не нужно. Функция называется по-разному: DHCP reservation, static DHCP, address reservation. Перезагрузите сервер (или обновите аренду), чтобы получить адрес.

## 3. Вариант B: статический IP через netplan

Netplan — слой сетевой конфигурации Ubuntu (YAML-файлы в `/etc/netplan/`). Выберите адрес вне диапазона DHCP роутера.

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

- Отступы только пробелами, по 2 на уровень. Табуляция или неверный отступ делают файл недействительным.
- `routes: to: default` заменяет устаревший `gateway4`.
- Файлы netplan не должны быть доступны всем: `sudo chmod 600 /etc/netplan/*.yaml`.
- Имя файла может отличаться (`00-installer-config.yaml`); правьте существующий.

Применяйте с автоматическим откатом, чтобы ошибка не лишила доступа:

```bash
sudo netplan try        # нажмите Enter в течение 120 с, иначе изменения откатятся
sudo netplan apply
```

> **Warning:** запускайте `netplan try` из консоли или SSH-сессии, которую не жалко потерять. При смене IP текущая SSH-сессия оборвётся; подключитесь заново по новому адресу.

## 4. Имя хоста и часовой пояс

```bash
sudo hostnamectl set-hostname <SERVER_HOSTNAME>
sudo timedatectl set-timezone Europe/Berlin     # ваш пояс: timedatectl list-timezones
timedatectl set-ntp true
```

Если в `/etc/hosts` есть строка `127.0.1.1` со старым именем хоста, замените его на `<SERVER_HOSTNAME>`.

## 5. Разрешение имён на сервере

```bash
resolvectl query ubuntu.com
ping -c2 1.1.1.1 && ping -c2 ubuntu.com
```

Если по IP отвечает, а по имени нет — сломан DNS: перепроверьте `nameservers` в файле netplan.

## 6. Разрешение `*.<DOMAIN_BASE>` на ноутбуке

Проекты открываются по именам вроде `<PROJECT_NAME>.<DOMAIN_BASE>`, Traefik маршрутизирует их по заголовку `Host`. В частной сети публичной DNS-записи нет, поэтому ноутбук должен сам сопоставить имена с `<SERVER_IP>`.

| Способ | Когда | Как |
|---|---|---|
| Файл `hosts` | Несколько проектов, один ноутбук | Одна строка на имена, ниже |
| Локальный DNS (роутер или `dnsmasq`) | Много имён или устройств | Wildcard `address=/<DOMAIN_BASE>/<SERVER_IP>` |
| Публичная A-запись DNS | Облачный сервер с публичным IP | См. [Local vs cloud differences](../00-overview/local-vs-cloud-differences.md) |

Расположение `hosts`: macOS/Linux `/etc/hosts` (правка через `sudo`).

```bash
echo "<SERVER_IP>  <PROJECT_NAME>.<DOMAIN_BASE> phpmyadmin.<PROJECT_NAME>.<DOMAIN_BASE>" | sudo tee -a /etc/hosts
# только macOS: сброс DNS-кэша
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

- Формат строгий: IP, затем имена через пробелы, одна строка. Без `http://` и без завершающего слэша.
- `hosts` не поддерживает wildcard; каждое имя нужно перечислить.
- Не используйте суффикс `.local` для `<DOMAIN_BASE>` на macOS/Linux: он зарезервирован под mDNS и может разрешаться медленно или не разрешаться вовсе. Лучше `.lab` или `.home.arpa`.

Локальный wildcard-DNS через `dnsmasq` (на сервере или любом постоянно включённом хосте сети), если он удобнее `hosts`:

```bash
sudo apt install dnsmasq -y
echo "address=/<DOMAIN_BASE>/<SERVER_IP>" | sudo tee /etc/dnsmasq.d/lab.conf
sudo systemctl restart dnsmasq
```

Затем укажите этот хост DNS-сервером на роутере или ноутбуке. На машине с `systemd-resolved` (по умолчанию в Ubuntu) порт 53 занят stub-резолвером; сначала задайте `DNSStubListener=no` в `/etc/systemd/resolved.conf` либо запустите dnsmasq на другом хосте.

## Wi-Fi

Для узла K3s используйте Ethernet. Health-проверки Kubernetes воспринимают короткое зависание Wi-Fi как отказ узла, и поды случайно перезапускаются. У некоторых Wi-Fi-чипов вообще нет драйвера в ядре. Если Wi-Fi — единственный вариант или чип не определяется, см. [Troubleshooting networking](../99-appendix/troubleshooting-networking.md); надёжная замена — USB Wi-Fi адаптер на давно поддерживаемом чипсете.

## Verify

```bash
ip -br a                       # <SERVER_IP> на интерфейсе
ip route | grep default
hostnamectl                    # имя хоста; пояс: timedatectl
ping -c2 ubuntu.com
```

С ноутбука:

```bash
ping -c2 <SERVER_IP>
ping -c2 <PROJECT_NAME>.<DOMAIN_BASE>     # разрешается в <SERVER_IP>
ssh <SERVER_USER>@<SERVER_IP>
```

Перезагрузитесь один раз (`sudo reboot`) и убедитесь, что адрес не изменился.

Next: [SSH hardening](../02-security/ssh-hardening.md)
