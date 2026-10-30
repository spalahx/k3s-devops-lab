# Установка Docker Engine

Устанавливает Docker Engine из официального apt-репозитория Docker и позволяет обычному пользователю работать с ним без `sudo`. Docker нужен для сборки и проверки образов; сам K3s работает на встроенном containerd и Docker ему не требуется, поэтому эту страницу можно пропустить, если вы разворачиваете только готовые образы.

## 1. Подключение apt-репозитория Docker

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

## 2. Установка пакетов

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

`enable --now` запускает Docker сразу и при каждой загрузке.

> **Note:** пакет из репозитория дистрибутива `docker.io` тоже подходит и ставится проще (`sudo apt install -y docker.io`), но его версия отстаёт от upstream.

## 3. Работа с Docker без sudo

```bash
sudo usermod -aG docker <SERVER_USER>
```

> **Warning:** членство в группе применяется только к новым сессиям входа. Выйдите и подключитесь по SSH заново (или выполните `newgrp docker` в текущем шелле), иначе `docker ps` вернёт `permission denied`. Участник группы `docker` фактически имеет root-доступ к машине; добавляйте только доверенных пользователей.

## Проверка

```bash
docker --version
docker run --rm hello-world
sudo systemctl is-active docker
```

`hello-world` печатает "Hello from Docker!"; `is-active` возвращает `active`.

| Симптом | Решение |
|---|---|
| `permission denied` на `/var/run/docker.sock` | Перелогиниться после `usermod` или выполнить `newgrp docker` |
| `Unable to locate package docker-ce` | Нет файла репозитория или неверный codename; проверьте `cat /etc/apt/sources.list.d/docker.list` |
| `hello-world` не скачивается | Нет выхода в интернет/DNS с сервера; проверьте `ping 8.8.8.8` и `getent hosts registry-1.docker.io` |

Next: [Установка K3s](k3s-install.md)
