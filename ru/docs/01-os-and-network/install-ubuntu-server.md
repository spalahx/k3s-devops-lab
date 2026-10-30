# Установка Ubuntu Server

Устанавливает Ubuntu Server LTS на «голую» машину с USB-флешки. Пропустите, если сервер — облачный VPS с уже установленной Ubuntu (см. [Local vs cloud differences](../00-overview/local-vs-cloud-differences.md)).

## 1. Выбор образа

| Параметр | Значение |
|---|---|
| Дистрибутив | Ubuntu Server (без графики), последняя LTS (например 24.04 LTS; LTS = 5 лет обновлений безопасности) |
| Архитектура | `amd64` для Intel/AMD, `arm64` для ARM-плат. Образ неверной архитектуры не загрузится |
| Загрузка | `https://ubuntu.com/download/server` (ISO около 2 ГБ) |

Проверьте контрольную сумму SHA256 с опубликованной на сайте:

```bash
# macOS
shasum -a 256 ~/Downloads/ubuntu-*-live-server-amd64.iso
# Linux
sha256sum ~/Downloads/ubuntu-*-live-server-amd64.iso
```

## 2. Запись USB-флешки

Нужна флешка от 8 ГБ. Все данные на ней будут стёрты.

### macOS

```bash
diskutil list                         # найдите флешку по размеру, например /dev/disk4 (external, physical)
diskutil unmountDisk /dev/diskN
sudo dd if=~/Downloads/ubuntu-XX.XX-live-server-amd64.iso of=/dev/rdiskN bs=1m status=progress
diskutil eject /dev/diskN
```

### Linux

```bash
lsblk                                 # найдите флешку, например /dev/sdb (не раздел вроде sdb1)
sudo umount /dev/sdb* 2>/dev/null
sudo dd if=~/Downloads/ubuntu-XX.XX-live-server-amd64.iso of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

- `rdiskN` в macOS — «сырое» устройство, запись через него заметно быстрее, чем через `diskN`.
- `dd` не спрашивает подтверждения. Неверный `of=` (например внутренний диск `disk0`) уничтожит этот диск. Дважды сверьте размер в `diskutil list` / `lsblk`.
- `Resource busy` на macOS — флешка всё ещё смонтирована: повторите `diskutil unmountDisk`.

## 3. Загрузка с USB

1. Подключите машину кабелем Ethernet к роутеру. Устанавливайте по проводу: установщик скачивает пакеты, а у некоторых Wi-Fi-чипов нет драйвера в установщике (см. [Troubleshooting networking](../99-appendix/troubleshooting-networking.md)).
2. Подключите монитор и клавиатуру (нужны только до появления SSH).
3. Вставьте флешку, включите питание и многократно нажимайте клавишу Boot Menu (обычно `F7`, `F10`, `F11`, `F12`, `Esc` или `Del`, зависит от производителя).
4. Выберите пункт, начинающийся с `UEFI:` и названием флешки. Не выбирайте `Legacy`.

Если флешки нет в списке: попробуйте другой USB-порт (лучше USB 2.0), перезапишите флешку другой утилитой, проверьте, что Secure Boot не блокирует загрузку (ISO Ubuntu подписан и обычно грузится и с Secure Boot).

## 4. Выбор в установщике

Установщик текстовый: стрелки, `Tab`, `Space` (отметить), `Enter`.

| Экран | Выбор |
|---|---|
| Язык / клавиатура | English (сообщения об ошибках проще искать) |
| Тип установки | `Ubuntu Server` (не minimized) |
| Сеть | У проводного интерфейса должен быть адрес по DHCP. Оставьте как есть; статический IP задаётся позже ([Static IP](static-ip-and-networking.md)) |
| Прокси / зеркало | По умолчанию |
| Диск | Use an entire disk, оставьте включённым «Set up this disk as an LVM group» (разделы можно будет менять позже). Выберите внутренний диск, не флешку |
| Профиль | Ваше имя, имя сервера `<SERVER_HOSTNAME>`, пользователь `<SERVER_USER>`, надёжный пароль (он нужен для `sudo` и после отключения входа по паролю в SSH) |
| Ubuntu Pro | Пропустить |
| SSH | **Отметьте «Install OpenSSH server»**. Импорт ключей сейчас не нужен |
| Featured snaps | Ничего не выбирать |

Дождитесь окончания установки и обновлений (10–20 минут), выберите **Reboot**. Когда попросят, **выньте флешку** до нажатия `Enter`, иначе машина снова загрузит установщик.

> **Warning:** если OpenSSH server не был отмечен, установите его в консоли: `sudo apt install openssh-server`.

## 5. Первый вход и обновление

В консоли войдите как `<SERVER_USER>` (пароль при вводе не отображается). Узнайте адрес:

```bash
ip -br a
```

Пример: `enp1s0  UP  192.168.1.150/24`. Имена интерфейсов (`enp1s0`, `eno1`, `eth0`) зависят от машины.

Дальше работайте с ноутбука; монитор и клавиатура больше не нужны:

```bash
ssh <SERVER_USER>@<SERVER_IP>
```

На вопрос об отпечатке хоста при первом подключении ответьте `yes` (он сохраняется в `~/.ssh/known_hosts` и предупредит, если хост позже изменится). Затем обновите систему:

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot        # если обновились ядро или libc
```

## Verify

```bash
lsb_release -d                       # Ubuntu LTS
systemctl is-active ssh              # active
ip -br a                             # у проводного интерфейса есть адрес
sudo apt update && apt list --upgradable   # обновлений не осталось (или только удержанные)
```

## Частые проблемы

| Симптом | Причина / решение |
|---|---|
| Установщик не видит сеть | Переставьте кабель, попробуйте другой кабель/порт, проверьте DHCP на роутере |
| `ssh: Connection timed out` | Неверный IP или ноутбук в другой сети; перепроверьте `ip -br a` на сервере |
| `ssh: Connection refused` | OpenSSH server не установлен или не запущен: `sudo apt install openssh-server && systemctl status ssh` |
| Забыт пароль пользователя | Нужен доступ к консоли и режим восстановления GRUB либо переустановка |

Next: [Static IP and networking](static-ip-and-networking.md)
