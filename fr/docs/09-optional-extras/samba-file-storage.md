# Stockage de fichiers Samba

Expose un dossier du serveur comme lecteur réseau (SMB) que les portables macOS et Linux peuvent monter pour échanger des fichiers par glisser-déposer (dumps SQL, images, manifestes). Optionnel : ignorez-le sur un VPS cloud (SMB ne doit jamais faire face à Internet) et lorsque `scp`/`rsync`/IDE Remote-SSH suffisent.

Samba conserve sa propre base de mots de passe, distincte du mot de passe Linux et des clés SSH. Une connexion SSH réussie ne donne pas accès à SMB tant que `smbpasswd` n'a pas été défini pour cet utilisateur.

## 1. Installation

```bash
sudo apt update && sudo apt install -y samba
sudo systemctl enable --now smbd
systemctl status smbd --no-pager
```

`smbd` sert les fichiers ; le service optionnel `nmbd` (découverte de noms NetBIOS) n'est pas nécessaire pour se connecter par IP.

## 2. Créer le dossier partagé

Partagez un répertoire dédié, pas tout le répertoire personnel : partager `/home/<SERVER_USER>` exposerait aussi `~/.ssh`, `~/.kube` et l'historique du shell.

```bash
mkdir -p /home/<SERVER_USER>/share
chmod 0775 /home/<SERVER_USER>/share
```

## 3. Configurer le partage

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
sudo nano /etc/samba/smb.conf
```

Ajoutez à la fin :

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

| Option | Signification |
|---|---|
| `[share]` | Nom du partage utilisé dans l'adresse de connexion |
| `path` | Répertoire réel sur le serveur |
| `read only = no` | Autorise l'écriture via le réseau |
| `valid users` | Seuls ces utilisateurs Samba peuvent accéder à ce partage |
| `create mask` / `directory mask` | Permissions des nouveaux fichiers / répertoires créés via SMB |
| `hosts allow` / `hosts deny` | Restreint au sous-réseau local (adaptez le CIDR au LAN réel) |

Durcissement global optionnel, dans la section `[global]` existante :

```ini
   server min protocol = SMB2
```

Validez :

```bash
testparm -s
```

## 4. Définir le mot de passe Samba

L'utilisateur Linux doit déjà exister ; `smbpasswd -a` enregistre seulement un mot de passe Samba pour lui.

```bash
sudo smbpasswd -a <SERVER_USER>
sudo systemctl restart smbd
```

Modifiez-le plus tard avec `sudo smbpasswd <SERVER_USER>`.

## 5. Ouvrir le pare-feu (LAN uniquement)

N'utilisez pas `ufw allow samba` sans source : cela ouvre SMB à tout ce qui peut atteindre l'hôte. Limitez-le au sous-réseau du LAN :

```bash
sudo ufw allow from 192.168.1.0/24 to any app Samba
sudo ufw status
```

## 6. Monter depuis le portable

Utilisez l'IP fixe du serveur (`<SERVER_IP>`, voir [IP fixe](../01-os-and-network/static-ip-and-networking.md)).

**macOS** (Finder -> Aller -> Se connecter au serveur, ou `Cmd+K`) :

```
smb://<SERVER_IP>/share
```

Choisissez « Utilisateur enregistré », saisissez `<SERVER_USER>` et le mot de passe Samba. Le volume apparaît sous Emplacements. Depuis un terminal :

```bash
mkdir -p ~/mnt/server && mount_smbfs //<SERVER_USER>@<SERVER_IP>/share ~/mnt/server
```

**Linux** :

```bash
sudo apt install -y cifs-utils
printf 'username=<SERVER_USER>\npassword=<SAMBA_PASSWORD>\n' > ~/.smbcred && chmod 600 ~/.smbcred
sudo mkdir -p /mnt/server
sudo mount -t cifs //<SERVER_IP>/share /mnt/server -o credentials=$HOME/.smbcred,uid=$(id -u),gid=$(id -g)
```

`<SAMBA_PASSWORD>` est le mot de passe défini à l'étape 4. Pour un montage permanent, ajoutez les mêmes options sous forme de ligne `/etc/fstab` avec `_netdev,nofail`.

## Vérification

```bash
# Sur le serveur
sudo ss -tlnp | grep -E ':(139|445)\b'
smbclient -L localhost -U <SERVER_USER>
```

Depuis le portable : créez un fichier dans le lecteur monté et vérifiez-le sur le serveur avec `ls -l /home/<SERVER_USER>/share`.

## Pièges courants

| Symptôme | Cause / solution |
|---|---|
| Mot de passe rejeté à répétition | Vous avez saisi le mot de passe Linux/SSH ; utilisez celui de `smbpasswd` |
| Partage invisible | Erreur de syntaxe dans `smb.conf` (exécutez `testparm`), ou `hosts allow` n'inclut pas le sous-réseau du client |
| `Connection failed` / délai dépassé | `smbd` non démarré, règle UFW manquante ou client sur un autre sous-réseau |
| `Permission denied` à l'écriture | Permissions Linux sur `path` (`ls -ld`), `valid users` ou masques ; corrigez avec `chown`/`chmod 0775` |
| Partage disparu après un redémarrage | Service non activé : `systemctl is-enabled smbd` |
| La connexion se rompt quand l'IP du serveur change | Réservez l'IP dans le routeur ou utilisez l'adressage statique netplan |

Suite : [Ollama dans un namespace dédié](ollama-ai-namespace.md)
