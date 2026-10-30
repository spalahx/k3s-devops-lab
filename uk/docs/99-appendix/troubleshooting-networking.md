# Усунення мережевих проблем (лише локальне обладнання)

Діагностика відсутнього або нестабільного мережевого адаптера, переважно Wi-Fi, на фізичній машині. Не стосується VPS. Якщо сервер має Ethernet, користуйтеся ним і повністю оминайте Wi-Fi.

Виконуйте кроки по порядку; зупиніться на першому, що пояснює симптом.

## 1. Чи є інтерфейс?

```bash
ip link
ip -br addr
```

Очікуйте `lo`, назву Ethernet-інтерфейсу на кшталт `enp2s0`, а для Wi-Fi запис `wlan0`/`wlp*`. Віртуальні `cni0`, `flannel.1`, `veth*`, `docker0` належать контейнерам і нічого не кажуть про фізичні адаптери.

## 2. Чи заблоковано його програмно?

```bash
rfkill list
sudo rfkill unblock wifi
```

`Soft blocked: yes` виправляється розблокуванням. Якщо адаптера немає і в `rfkill list`, проблема глибша (драйвер).

## 3. Чи існує пристрій на шині?

```bash
lspci -nn | grep -iE 'network|wireless|wifi|ethernet'
lsusb
```

| Результат | Значення |
|---|---|
| Пристрій у списку з ідентифікатором `[vendor:device]` | З обладнанням усе гаразд; драйвера немає або він працює збійно. Запишіть ідентифікатор |
| Немає в списку | Фізична проблема: перевстановіть картку M.2, перевірте налаштування BIOS (адаптер вимкнено), спробуйте інший USB-порт |

## 4. Драйвер і прошивка

```bash
lspci -nnk | grep -iA3 'network'      # рядок "Kernel driver in use:"
sudo dmesg | grep -iE 'firmware|wlan|wifi|iwlwifi|ath|rtw|mt79|r8169|e1000|enp'
uname -r
```

- Немає рядка `Kernel driver in use`: до пристрою не прив'язано жодного драйвера.
- `firmware: failed to load` або `-2`: встановіть прошивку, потім перезавантажте.

```bash
sudo apt update
sudo apt install --reinstall linux-firmware
```

- Перевірте, чи модуль драйвера охоплює ваш ідентифікатор (`modinfo <module> | grep -i alias`, шукайте частину ідентифікатора, що позначає пристрій).
- Нові чипи часто підтримуються лише в новіших ядрах. Спочатку оновіть систему; у випуску LTS встановіть ядро HWE:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install linux-generic-hwe-$(lsb_release -rs)
sudo reboot
```

- Примусове призначення непідтримуваного ідентифікатора спорідненому драйверу через `new_id` зазвичай завершується помилкою `Invalid argument`, якщо чип внутрішньо відрізняється; не покладайтеся на це:

```bash
echo "<vendor> <device>" | sudo tee /sys/bus/pci/drivers/<module>/new_id
```

> **Попередження:** Драйвер, зібраний вручну поза деревом ядра, непомітно ламається після наступного оновлення ядра, і сервер без монітора зникає з мережі. K3s реагує на збої мережі перезапуском Pod. Для сервера обирайте Ethernet або USB-адаптер Wi-Fi, чий чип підтримується драйвером у складі ядра.

## 5. Конфігурація netplan

Назви інтерфейсів у netplan мають збігатися з виводом `ip link`. Файли розташовані в `/etc/netplan/`.

```yaml
# /etc/netplan/50-wifi.yaml  (приклад Wi-Fi, права 600)
network:
  version: 2
  renderer: networkd
  wifis:
    wlan0:
      dhcp4: true
      access-points:
        "<WIFI_SSID>":
          password: "<WIFI_PASSWORD>"
```

```bash
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan try        # відкочується за 120 с, якщо зв'язок втрачено
sudo netplan apply
```

Для Wi-Fi має бути встановлено `wpasupplicant` (`sudo apt install wpasupplicant`). `<WIFI_SSID>` і `<WIFI_PASSWORD>` — назва та ключ вашої мережі. Статична адресація: [Статична IP-адреса та мережа](../01-os-and-network/static-ip-and-networking.md).

## 6. Енергозбереження Wi-Fi

Симптоми: висока затримка, SSH зависає після простою. Перевірте та вимкніть:

```bash
iw dev wlan0 get power_save
sudo iw dev wlan0 set power_save off
```

Щоб зробити це постійним, якщо використовується NetworkManager, створіть `/etc/NetworkManager/conf.d/wifi-powersave.conf` із секцією `[connection]` і `wifi.powersave = 2`. У networkd скористайтеся юнітом systemd або правилом udev, що під час завантаження виконує наведену вище команду `iw`.

## 7. DNS і маршрутизація

З'єднання є, але імена не розпізнаються:

```bash
ip route                         # маршрут за замовчуванням існує?
ping -c2 1.1.1.1                 # IP-зв'язність
ping -c2 example.com             # розпізнавання імен
resolvectl status                # DNS-сервери для кожного інтерфейсу
```

- IP працює, імена ні: задайте в netplan `nameservers: addresses: [1.1.1.1, 8.8.8.8]` і застосуйте.
- Немає маршруту за замовчуванням: у статичній конфігурації помилковий шлюз.
- Два маршрути за замовчуванням (Ethernet і Wi-Fi одночасно активні): задайте `dhcp4-overrides: {route-metric: 600}` для вторинного інтерфейсу.

## 8. Крайні заходи

- Після оновлення ядра мережа зникла: завантажте старіше ядро з меню GRUB «Advanced options» або підключіть Ethernet.
- Перш ніж звинувачувати драйвери, перевірте кабель, порт комутатора та таблицю DHCP-оренд на роутері.

Далі: [Глосарій](glossary.md)
