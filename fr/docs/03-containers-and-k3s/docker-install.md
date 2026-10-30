# Installation de Docker Engine

Installe Docker Engine depuis le dépôt apt officiel de Docker et permet à l'utilisateur standard de l'exécuter sans `sudo`. Docker sert à construire et tester des images ; K3s fonctionne avec son propre containerd intégré et n'a pas besoin de Docker, vous pouvez donc ignorer cette page si vous ne déployez que des images déjà construites.

## 1. Ajouter le dépôt apt de Docker

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

## 2. Installer les paquets

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

`enable --now` démarre Docker immédiatement et à chaque démarrage de la machine.

> **Note :** le paquet `docker.io` de la distribution fonctionne aussi et est plus simple (`sudo apt install -y docker.io`), mais il est en retard sur les versions amont.

## 3. Utiliser Docker sans sudo

```bash
sudo usermod -aG docker <SERVER_USER>
```

> **Attention :** l'appartenance à un groupe ne s'applique qu'aux nouvelles sessions. Déconnectez-vous puis reconnectez-vous en SSH (ou exécutez `newgrp docker` dans le shell courant), sinon `docker ps` échoue avec `permission denied`. Les membres du groupe `docker` sont en pratique root sur la machine ; n'ajoutez que des utilisateurs de confiance.

## Vérification

```bash
docker --version
docker run --rm hello-world
sudo systemctl is-active docker
```

`hello-world` affiche « Hello from Docker! » ; `is-active` affiche `active`.

| Symptôme | Solution |
|---|---|
| `permission denied` sur `/var/run/docker.sock` | Se reconnecter après `usermod`, ou `newgrp docker` |
| `Unable to locate package docker-ce` | Le fichier du dépôt est absent ou le nom de code est incorrect ; vérifiez avec `cat /etc/apt/sources.list.d/docker.list` |
| `hello-world` ne peut pas être téléchargé | Pas d'accès Internet/DNS sortant depuis le serveur ; testez `ping 8.8.8.8` et `getent hosts registry-1.docker.io` |

Suite : [Installation de K3s](k3s-install.md)
