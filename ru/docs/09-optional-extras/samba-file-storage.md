# Samba: сетевое файловое хранилище

Публикует одну папку сервера как сетевой диск (SMB), который можно подключить с ноутбука на macOS и Linux для обмена файлами (SQL-дампы, изображения, манифесты). Опционально: пропустите на облачном VPS (SMB нельзя выставлять в интернет) и когда хватает `scp`/`rsync`/IDE Remote-SSH.

У Samba собственная база паролей, отдельная от пароля Linux и SSH-ключей. Успешный вход по SSH не даёт доступа к SMB, пока для пользователя не задан `smbpasswd`.

## 1. Установка

```bash
sudo apt update && sudo apt install -y samba
sudo systemctl enable --now smbd
systemctl status smbd --no-pager
```

`smbd` раздаёт файлы; необязательный `nmbd` (NetBIOS-имена) при подключении по IP не нужен.

## 2. Создать общую папку

Публикуйте отдельный каталог, а не весь домашний: шаринг `/home/<SERVER_USER>` откроет также `~/.ssh`, `~/.kube` и историю shell.

```bash
mkdir -p /home/<SERVER_USER>/share
chmod 0775 /home/<SERVER_USER>/share
```

## 3. Настроить ресурс

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
sudo nano /etc/samba/smb.conf
```

Добавьте в конец файла:

```ini
[share]
   comment = Server file exchange
   path = /home/<SERVER_USER>/share
   read only = no
   browsable = yes
   valid users = <SERVER_USER>
   create mask = 0664
   directory mask = 0775
   hosts allow = 192.168.1.0/24 127.0.0.1
   hosts deny = 0.0.0.0/0
```

| Опция | Значение |
|---|---|
| `[share]` | Имя ресурса, используется в адресе подключения |
| `path` | Реальный каталог на сервере |
| `read only = no` | Разрешить запись по сети |
| `valid users` | Доступ к ресурсу только у этих пользователей Samba |
| `create mask` / `directory mask` | Права для новых файлов / каталогов, созданных через SMB |
| `hosts allow` / `hosts deny` | Ограничение локальной подсетью (подставьте CIDR своей LAN) |

Дополнительное ужесточение в существующей секции `[global]`:

```ini
   server min protocol = SMB2
```

Проверка:

```bash
testparm -s
```

## 4. Задать пароль Samba

Linux-пользователь должен уже существовать; `smbpasswd -a` лишь регистрирует для него пароль Samba.

```bash
sudo smbpasswd -a <SERVER_USER>
sudo systemctl restart smbd
```

Сменить позже: `sudo smbpasswd <SERVER_USER>`.

## 5. Открыть файрвол (только LAN)

Не используйте `ufw allow samba` без источника: это откроет SMB всем, кто достаёт до хоста. Ограничьте подсетью LAN:

```bash
sudo ufw allow from 192.168.1.0/24 to any app Samba
sudo ufw status
```

## 6. Подключить с ноутбука

Используйте статический IP сервера (`<SERVER_IP>`, см. [статический IP](../01-os-and-network/static-ip-and-networking.md)).

**macOS** (Finder -> Переход -> Подключиться к серверу, или `Cmd+K`):

```
smb://<SERVER_IP>/share
```

Выберите «Зарегистрированный пользователь», введите `<SERVER_USER>` и пароль Samba. Том появится в разделе «Места». Из терминала:

```bash
mkdir -p ~/mnt/server && mount_smbfs //<SERVER_USER>@<SERVER_IP>/share ~/mnt/server
```

**Linux**:

```bash
sudo apt install -y cifs-utils
printf 'username=<SERVER_USER>\npassword=<SAMBA_PASSWORD>\n' > ~/.smbcred && chmod 600 ~/.smbcred
sudo mkdir -p /mnt/server
sudo mount -t cifs //<SERVER_IP>/share /mnt/server -o credentials=$HOME/.smbcred,uid=$(id -u),gid=$(id -g)
```

`<SAMBA_PASSWORD>` — пароль из шага 4. Для постоянного монтирования добавьте те же опции строкой в `/etc/fstab` с `_netdev,nofail`.

## Verify

```bash
# На сервере
sudo ss -tlnp | grep -E ':(139|445)\b'
smbclient -L localhost -U <SERVER_USER>
```

С ноутбука: создайте файл на подключённом диске и проверьте на сервере `ls -l /home/<SERVER_USER>/share`.

## Gotchas

| Симптом | Причина / решение |
|---|---|
| Пароль постоянно отклоняется | Вводится пароль Linux/SSH; нужен пароль из `smbpasswd` |
| Ресурс не виден | Синтаксическая ошибка в `smb.conf` (запустите `testparm`) или `hosts allow` не включает подсеть клиента |
| `Connection failed` / таймаут | `smbd` не запущен, нет правила UFW или клиент в другой подсети |
| `Permission denied` при записи | Права Linux на `path` (`ls -ld`), `valid users` или маски; исправьте `chown`/`chmod 0775` |
| Ресурс пропал после перезагрузки | Служба не включена: `systemctl is-enabled smbd` |
| Подключение ломается при смене IP сервера | Зарезервируйте IP в роутере или используйте статику через netplan |

Next: [Ollama в отдельном namespace](ollama-ai-namespace.md)
