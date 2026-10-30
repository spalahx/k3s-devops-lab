# Файлове сховище Samba

Відкриває одну теку сервера як мережевий диск (SMB), який ноутбуки з macOS і Linux можуть змонтувати для обміну файлами перетягуванням (дампи SQL, образи, маніфести). Необов'язково: пропустіть на хмарному VPS (SMB ніколи не має дивитися в інтернет) і коли вистачає `scp`/`rsync`/IDE Remote-SSH.

Samba веде власну базу паролів, окрему від пароля Linux і ключів SSH. Успішний вхід за SSH не дає доступу до SMB, доки для цього користувача не задано `smbpasswd`.

## 1. Встановлення

```bash
sudo apt update && sudo apt install -y samba
sudo systemctl enable --now smbd
systemctl status smbd --no-pager
```

`smbd` віддає файли; необов'язковий `nmbd` (виявлення імен NetBIOS) не потрібен, якщо підключатися за IP-адресою.

## 2. Створення спільної теки

Публікуйте окрему теку, а не всю домашню теку: спільний доступ до `/home/<SERVER_USER>` відкрив би також `~/.ssh`, `~/.kube` та історію оболонки.

```bash
mkdir -p /home/<SERVER_USER>/share
chmod 0775 /home/<SERVER_USER>/share
```

## 3. Налаштування спільного ресурсу

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
sudo nano /etc/samba/smb.conf
```

Додайте в кінець:

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

| Опція | Значення |
|---|---|
| `[share]` | Назва ресурсу, що використовується в адресі підключення |
| `path` | Реальна тека на сервері |
| `read only = no` | Дозволити запис через мережу |
| `valid users` | Лише ці користувачі Samba мають доступ до цього ресурсу |
| `create mask` / `directory mask` | Права для нових файлів / тек, створених через SMB |
| `hosts allow` / `hosts deny` | Обмежити локальною підмережею (змініть CIDR відповідно до реальної LAN) |

Необов'язкове глобальне посилення захисту в наявній секції `[global]`:

```ini
   server min protocol = SMB2
```

Перевірка коректності:

```bash
testparm -s
```

## 4. Встановлення пароля Samba

Користувач Linux уже має існувати; `smbpasswd -a` лише реєструє для нього пароль Samba.

```bash
sudo smbpasswd -a <SERVER_USER>
sudo systemctl restart smbd
```

Змінити його пізніше можна за допомогою `sudo smbpasswd <SERVER_USER>`.

## 5. Відкриття брандмауера (лише LAN)

Не використовуйте `ufw allow samba` без джерела: це відкриває SMB для всіх, хто може досягти хоста. Обмежте його підмережею LAN:

```bash
sudo ufw allow from 192.168.1.0/24 to any app Samba
sudo ufw status
```

## 6. Монтування з ноутбука

Використовуйте статичну IP-адресу сервера (`<SERVER_IP>`, див. [статична IP-адреса](../01-os-and-network/static-ip-and-networking.md)).

**macOS** (Finder -> Go -> Connect to Server, або `Cmd+K`):

```
smb://<SERVER_IP>/share
```

Оберіть "Registered User", введіть `<SERVER_USER>` і пароль Samba. Том з'явиться в розділі Locations. З терміналу:

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

`<SAMBA_PASSWORD>` — це пароль, заданий на кроці 4. Для постійного монтування додайте ті самі опції рядком в `/etc/fstab` з `_netdev,nofail`.

## Перевірка

```bash
# На сервері
sudo ss -tlnp | grep -E ':(139|445)\b'
smbclient -L localhost -U <SERVER_USER>
```

З ноутбука: створіть файл на змонтованому диску й перевірте його на сервері за допомогою `ls -l /home/<SERVER_USER>/share`.

## Типові проблеми

| Симптом | Причина / виправлення |
|---|---|
| Пароль постійно відхиляється | Введено пароль Linux/SSH; використовуйте той, що з `smbpasswd` |
| Ресурс не видно | Синтаксична помилка в `smb.conf` (запустіть `testparm`) або `hosts allow` не містить підмережі клієнта |
| `Connection failed` / тайм-аут | `smbd` не запущено, немає правила UFW або клієнт в іншій підмережі |
| `Permission denied` під час запису | Права Linux на `path` (`ls -ld`), `valid users` або маски; виправте через `chown`/`chmod 0775` |
| Ресурс зникає після перезавантаження | Службу не ввімкнено: `systemctl is-enabled smbd` |
| З'єднання розривається, коли змінюється IP сервера | Зарезервуйте IP у роутері або використовуйте статичну адресацію netplan |

Далі: [Ollama в окремому namespace](ollama-ai-namespace.md)
