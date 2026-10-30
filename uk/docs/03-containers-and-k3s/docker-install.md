# Встановлення Docker Engine

Встановлює Docker Engine з офіційного apt-репозиторію Docker і дозволяє звичайному користувачеві запускати його без `sudo`. Docker потрібен для збирання та тестування образів; сам K3s працює на власному вбудованому containerd і Docker йому не потрібен, тож пропустіть цю сторінку, якщо розгортаєте лише готові образи.

## 1. Додайте apt-репозиторій Docker

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

## 2. Встановіть пакети

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

`enable --now` запускає Docker одразу та при кожному завантаженні системи.

> **Примітка:** пакет дистрибутива `docker.io` теж підходить і простіший (`sudo apt install -y docker.io`), але відстає від актуальних версій.

## 3. Запуск Docker без sudo

```bash
sudo usermod -aG docker <SERVER_USER>
```

> **Попередження:** членство в групі діє лише в нових сеансах входу. Вийдіть і підключіться по SSH знову (або виконайте `newgrp docker` у поточній оболонці), інакше `docker ps` завершиться помилкою `permission denied`. Члени групи `docker` фактично є root на цій машині; додавайте лише довірених користувачів.

## Перевірка

```bash
docker --version
docker run --rm hello-world
sudo systemctl is-active docker
```

`hello-world` виводить "Hello from Docker!"; `is-active` виводить `active`.

| Симптом | Рішення |
|---|---|
| `permission denied` на `/var/run/docker.sock` | Увійдіть знову після `usermod` або виконайте `newgrp docker` |
| `Unable to locate package docker-ce` | Файл репозиторію відсутній або кодове ім'я хибне; перевірте `cat /etc/apt/sources.list.d/docker.list` |
| `hello-world` не може завантажити образ | Немає вихідного інтернету/DNS на сервері; перевірте `ping 8.8.8.8` і `getent hosts registry-1.docker.io` |

Далі: [Встановлення K3s](k3s-install.md)
