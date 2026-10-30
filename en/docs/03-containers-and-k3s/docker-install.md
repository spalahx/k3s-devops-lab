# Docker Engine Install

Installs Docker Engine from the official Docker apt repository and lets the regular user run it without `sudo`. Docker is used to build and test images; K3s itself runs on its own embedded containerd and does not need Docker, so skip this page if you only deploy prebuilt images.

## 1. Add the Docker apt repository

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

## 2. Install the packages

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

`enable --now` starts Docker immediately and on every boot.

> **Note:** the distro package `docker.io` also works and is simpler (`sudo apt install -y docker.io`), but it lags behind upstream versions.

## 3. Run Docker without sudo

```bash
sudo usermod -aG docker <SERVER_USER>
```

> **Warning:** group membership applies only to new login sessions. Log out and reconnect over SSH (or run `newgrp docker` in the current shell), otherwise `docker ps` fails with `permission denied`. Members of the `docker` group are effectively root on the machine; add only trusted users.

## Verify

```bash
docker --version
docker run --rm hello-world
sudo systemctl is-active docker
```

`hello-world` prints "Hello from Docker!"; `is-active` prints `active`.

| Symptom | Fix |
|---|---|
| `permission denied` on `/var/run/docker.sock` | Re-login after `usermod`, or `newgrp docker` |
| `Unable to locate package docker-ce` | Repo file is missing or the codename is wrong; check `cat /etc/apt/sources.list.d/docker.list` |
| `hello-world` cannot pull | No outbound internet/DNS from the server; test `ping 8.8.8.8` and `getent hosts registry-1.docker.io` |

Next: [K3s install](k3s-install.md)
