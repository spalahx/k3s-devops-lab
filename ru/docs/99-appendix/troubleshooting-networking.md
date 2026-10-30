# Диагностика сети (только локальное железо)

Диагностика отсутствующего или нестабильного сетевого адаптера, чаще всего Wi-Fi, на физической машине. К VPS не относится. Если у сервера есть Ethernet, используйте его и Wi-Fi не настраивайте.

Идите по шагам по порядку и остановитесь на первом, который объясняет симптом.

## 1. Интерфейс есть?

```bash
ip link
ip -br addr
```

Ожидается `lo`, Ethernet (например, `enp2s0`) и для Wi-Fi запись `wlan0`/`wlp*`. Виртуальные `cni0`, `flannel.1`, `veth*`, `docker0` относятся к контейнерам и ничего не говорят о физических адаптерах.

## 2. Заблокирован программно?

```bash
rfkill list
sudo rfkill unblock wifi
```

`Soft blocked: yes` лечится командой unblock. Если адаптера нет и в `rfkill list`, проблема глубже (драйвер).

## 3. Устройство есть на шине?

```bash
lspci -nn | grep -iE 'network|wireless|wifi|ethernet'
lsusb
```

| Результат | Значение |
|---|---|
| Устройство показано с ID `[vendor:device]` | Железо в порядке; драйвер отсутствует или не работает. Запишите ID |
| Не показано | Физическая проблема: переустановить M.2-карту, проверить BIOS (адаптер отключён), попробовать другой USB-порт |

## 4. Драйвер и firmware

```bash
lspci -nnk | grep -iA3 'network'      # строка "Kernel driver in use:"
sudo dmesg | grep -iE 'firmware|wlan|wifi|iwlwifi|ath|rtw|mt79|r8169|e1000|enp'
uname -r
```

- Нет строки `Kernel driver in use`: драйвер к устройству не привязан.
- `firmware: failed to load` или `-2`: установить firmware и перезагрузиться.

```bash
sudo apt update
sudo apt install --reinstall linux-firmware
```

- Проверьте, покрывает ли ваш ID какой-либо модуль (`modinfo <module> | grep -i alias`, ищите device-часть ID).
- Новые чипы нередко поддерживаются только в более свежих ядрах. Сначала обновите систему; на LTS-релизе поставьте ядро HWE:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install linux-generic-hwe-$(lsb_release -rs)
sudo reboot
```

- Принудительная привязка неподдерживаемого ID к родственному драйверу через `new_id` обычно заканчивается `Invalid argument`, если чип внутри отличается; на это не стоит рассчитывать:

```bash
echo "<vendor> <device>" | sudo tee /sys/bus/pci/drivers/<module>/new_id
```

> **Warning:** Драйвер, собранный вручную из исходников вне ядра, молча ломается после следующего обновления ядра, и безголовый сервер пропадает из сети. K3s реагирует на подвисания сети перезапуском Pod. Для сервера выберите Ethernet или USB Wi-Fi адаптер на чипе, поддерживаемом штатным драйвером ядра.

## 5. Конфигурация netplan

Имена интерфейсов в netplan должны совпадать с выводом `ip link`. Файлы лежат в `/etc/netplan/`.

```yaml
# /etc/netplan/50-wifi.yaml  (пример для Wi-Fi, права 600)
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
sudo netplan try        # откат через 120 с, если связь пропала
sudo netplan apply
```

Для Wi-Fi нужен `wpasupplicant` (`sudo apt install wpasupplicant`). `<WIFI_SSID>` и `<WIFI_PASSWORD>` — имя и пароль вашей сети. Статический адрес: [Статический IP и сеть](../01-os-and-network/static-ip-and-networking.md).

## 6. Энергосбережение Wi-Fi

Симптомы: высокая задержка, зависание SSH после простоя. Проверка и отключение:

```bash
iw dev wlan0 get power_save
sudo iw dev wlan0 set power_save off
```

Чтобы настройка сохранялась, при использовании NetworkManager создайте `/etc/NetworkManager/conf.d/wifi-powersave.conf` с секцией `[connection]` и `wifi.powersave = 2`. При networkd — systemd-юнит или правило udev, которое выполняет команду `iw` при загрузке.

## 7. DNS и маршрутизация

Соединение есть, но имена не резолвятся:

```bash
ip route                         # есть маршрут по умолчанию?
ping -c2 1.1.1.1                 # связь по IP
ping -c2 example.com             # разрешение имён
resolvectl status                # DNS-серверы по интерфейсам
```

- По IP работает, по именам нет: задайте `nameservers: addresses: [1.1.1.1, 8.8.8.8]` в netplan и примените.
- Нет маршрута по умолчанию: неверный шлюз в статической конфигурации.
- Два маршрута по умолчанию (Ethernet и Wi-Fi одновременно): укажите `dhcp4-overrides: {route-metric: 600}` для второстепенного интерфейса.

## 8. Крайние меры

- После обновления ядра сеть пропала: загрузитесь со старым ядром через GRUB (меню "Advanced options") или подключите Ethernet.
- Прежде чем винить драйверы, проверьте кабель, порт коммутатора и таблицу DHCP-аренд роутера.

Далее: [Глоссарий](glossary.md)
