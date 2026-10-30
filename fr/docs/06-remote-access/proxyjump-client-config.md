# Configuration client ProxyJump

Configure `~/.ssh/config` sur le portable afin qu'un seul alias, `ssh home-server`, fonctionne aussi bien sur le réseau local (connexion directe) qu'à distance (via le VPS et le tunnel inverse). Nécessite que le [tunnel inverse](reverse-ssh-tunnel-systemd.md) soit actif. `ProxyJump` (`-J`) indique au client SSH d'ouvrir une connexion vers un hôte intermédiaire et d'y faire transiter la connexion réelle.

## 1. Entrées pour l'accès à distance

```
Host vps-gateway
    HostName <VPS_IP>
    User <VPS_USER>
    Port <SSH_PORT>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host home-server-remote
    HostName 127.0.0.1
    Port <TUNNEL_PORT>
    User <SERVER_USER>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ProxyJump vps-gateway
    # Le port loopback du VPS a une identité de clé d'hôte différente de l'adresse LAN
    HostKeyAlias <SERVER_HOSTNAME>
    ServerAliveInterval 30
```

Ici, `127.0.0.1` est résolu sur le VPS (le dernier saut), là où le tunnel écoute. Test :

```bash
ssh home-server-remote
```

> **Avertissement :** n'utilisez pas `ProxyJump` vers l'IP LAN du serveur domestique (`<SERVER_IP>`) via le VPS : le VPS ne peut pas atteindre le réseau local de la maison. Le chemin est toujours portable -> VPS -> port du tunnel -> serveur domestique.

## 2. Un seul alias pour la maison et l'extérieur

`ssh_config` utilise la première valeur obtenue pour chaque option ; placez donc le bloc conditionnel avant le bloc générique. `Match ... exec` exécute une commande ; si elle réussit, le bloc s'applique.

```
# Joignable sur le LAN -> connexion directe
Match host home-server exec "nc -z -G 1 <SERVER_IP> <SSH_PORT> 2>/dev/null"
    HostName <SERVER_IP>
    Port <SSH_PORT>
    ProxyJump none

Host home-server
    HostName 127.0.0.1
    Port <TUNNEL_PORT>
    ProxyJump vps-gateway
    HostKeyAlias <SERVER_HOSTNAME>

Host home-server
    User <SERVER_USER>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 30
```

| Élément | Raison |
|---|---|
| `nc -z -G 1` | macOS : sonde TCP avec délai d'1 s. Sous Linux, utilisez `-w 1` au lieu de `-G 1` |
| `ProxyJump none` | Nécessaire pour annuler le saut, car le bloc `Host` suivant l'ajouterait sinon |
| `HostKeyAlias` | Les deux chemins présentent la même clé de serveur sous un seul nom, donc `known_hosts` reste cohérent et il n'y a pas d'avertissement de clé d'hôte |

La vérification du LAN n'ajoute jusqu'à une seconde que lorsque vous êtes loin de la maison. Le nom d'hôte et le port sont pris dans le premier bloc qui les définit.

## 3. IDE et outils

Tout outil qui lit `~/.ssh/config` fonctionne avec l'alias : VS Code/Cursor Remote-SSH (`home-server` apparaît dans la liste des hôtes ; voir [IDE Remote-SSH](../04-git-and-ide/ide-remote-ssh.md)), `scp`, `rsync`, `git` via SSH.

```bash
scp ./file.txt home-server:~/
rsync -av ./dist/ home-server:~/site/
```

Commande ponctuelle sans modifier la configuration :

```bash
ssh -J <VPS_USER>@<VPS_IP>:<SSH_PORT> -p <TUNNEL_PORT> <SERVER_USER>@127.0.0.1
```

Pour `kubectl` depuis le portable, redirigez le port de l'API via le même alias :

```bash
ssh -N -L 6443:127.0.0.1:6443 home-server
```

## Vérification

```bash
ssh -G home-server | grep -Ei '^(hostname|port|proxyjump) '
ssh home-server hostname
```

À la maison, `-G` affiche `<SERVER_IP>` et aucun proxyjump ; à l'extérieur, il affiche `127.0.0.1`, `<TUNNEL_PORT>` et `proxyjump vps-gateway`. Ajoutez `-v` pour voir quels sauts sont empruntés.

| Symptôme | Cause / solution |
|---|---|
| `Connection closed by UNKNOWN port 65535` | Le tunnel est arrêté ; vérifiez le service sur le serveur domestique |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | `HostKeyAlias` manquant ou serveur réinstallé ; `ssh-keygen -R <SERVER_HOSTNAME>` |
| Passe toujours par le VPS à la maison | La sonde LAN échoue (pare-feu, `<SERVER_IP>` incorrect ou option `nc` inadaptée à votre OS) |
| `Permission denied (publickey)` | La clé publique du portable n'est pas dans `authorized_keys` de `<SERVER_USER>` sur le serveur domestique |

Suite : [Pipeline GitLab CI](../07-cicd/gitlab-ci-petproject-pipeline.md)
