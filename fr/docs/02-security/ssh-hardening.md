# Renforcement de SSH

Configure la connexion SSH par clé uniquement pour un utilisateur sudo non root et déplace SSH du port 22 vers `<SSH_PORT>`. À faire sur tout serveur joignable depuis l'extérieur de sa propre pièce ; pour une machine purement locale, c'est quand même peu coûteux et une bonne habitude.

> **Avertissement :** pour ne pas vous enfermer dehors, gardez une session SSH fonctionnelle ouverte pendant toute la procédure et testez chaque changement depuis un second terminal. Si vous utilisez UFW, ouvrez `<SSH_PORT>` **avant** de changer le port SSH ([Pare-feu](firewall-ufw.md) étapes 1 à 3).

## 1. Utilisateur sudo non root

Ignorez cette étape si l'utilisateur de l'installeur `<SERVER_USER>` est déjà celui avec lequel vous travaillez. Pour ajouter un autre administrateur :

```bash
sudo adduser <SERVER_USER>
sudo usermod -aG sudo <SERVER_USER>      # -a est obligatoire : sans lui, tous les autres groupes sont retirés
su - <SERVER_USER>
sudo whoami                              # doit afficher : root
```

## 2. Authentification par clé depuis le portable

Sur le portable (macOS ou Linux), une clé par serveur ou par usage :

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "<GIT_PERSONAL_EMAIL>" -f ~/.ssh/<SERVER_HOSTNAME>
```

- `ed25519` est un type de clé moderne, court et rapide.
- Le commentaire (`-C`) n'est qu'une étiquette. Définissez une phrase secrète ; sur macOS, ajoutez `AddKeysToAgent yes` et `UseKeychain yes` au bloc `Host` ci-dessous pour éviter de la ressaisir.
- `~/.ssh/<SERVER_HOSTNAME>` est privée et ne quitte jamais le portable ; `.pub` est publique.

Copiez la clé publique (demande une fois le mot de passe du compte) :

```bash
ssh-copy-id -i ~/.ssh/<SERVER_HOSTNAME>.pub <SERVER_USER>@<SERVER_IP>
```

Si `ssh-copy-id` est absent (rare sous macOS), utilisez :

```bash
cat ~/.ssh/<SERVER_HOSTNAME>.pub | ssh <SERVER_USER>@<SERVER_IP> 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Ajoutez un alias client dans `~/.ssh/config` sur le portable (le port reste 22 pour l'instant) :

```
Host <SERVER_HOSTNAME>
    HostName <SERVER_IP>
    User <SERVER_USER>
    IdentityFile ~/.ssh/<SERVER_HOSTNAME>
    IdentitiesOnly yes
    Port 22
```

Testez, et ne continuez pas tant que la connexion ne réussit pas **sans le mot de passe du compte** :

```bash
ssh <SERVER_HOSTNAME>
```

## 3. Renforcer `sshd`

Ubuntu lit les fichiers complémentaires de `/etc/ssh/sshd_config.d/`, et la première valeur l'emporte ; un fichier préfixé par `01-` remplace donc les valeurs par défaut des images cloud (`50-cloud-init.conf` peut définir `PasswordAuthentication yes`).

```bash
sudo tee /etc/ssh/sshd_config.d/01-hardening.conf >/dev/null <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
CONF
sudo sshd -t && echo OK        # silence ou OK = la syntaxe est valide
sudo systemctl reload ssh
```

Ouvrez un **nouveau** terminal et vérifiez que `ssh <SERVER_HOSTNAME>` fonctionne toujours. Vérifiez les valeurs effectives :

```bash
sudo sshd -T | grep -E "^(passwordauthentication|permitrootlogin|pubkeyauthentication)"
```

## 4. Changer le port pour `<SSH_PORT>`

Choisissez un port libre supérieur à 1024 (par exemple `2222`). Appliquez dans cet ordre :

1. Autorisez-le d'abord dans le pare-feu (si UFW est actif) : `sudo ufw allow <SSH_PORT>/tcp`.
2. Ajoutez le port dans `sshd`, **en conservant 22 pour l'instant**.
3. Testez le nouveau port depuis un second terminal.
4. Seulement ensuite, supprimez le port 22.

Sur Ubuntu 22.10+ (dont 24.04), SSH est démarré par **activation par socket** : `ssh.socket` possède le port d'écoute et, selon la version, ignore `Port` dans `sshd_config`. Définissez le port sur le socket :

```bash
sudo mkdir -p /etc/systemd/system/ssh.socket.d
sudo tee /etc/systemd/system/ssh.socket.d/listen.conf >/dev/null <<'CONF'
[Socket]
ListenStream=
ListenStream=22
ListenStream=<SSH_PORT>
CONF
echo "Port <SSH_PORT>" | sudo tee /etc/ssh/sshd_config.d/02-port.conf
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo ss -tlnp | grep -E "sshd|:22 |:<SSH_PORT> "
```

- La ligne `ListenStream=` vide efface la valeur par défaut avant l'ajout des nouvelles valeurs.
- Si le système utilise un service classique sans socket (`systemctl status ssh.socket` indique `not-found`/`inactive`), seule la ligne `Port` dans `sshd_config` ou son fichier complémentaire est nécessaire, suivie de `sudo systemctl restart ssh`.

Mettez à jour l'alias sur le portable (`Port <SSH_PORT>`) et testez depuis un nouveau terminal :

```bash
ssh -p <SSH_PORT> <SERVER_USER>@<SERVER_IP>
```

Lorsque cela fonctionne de façon répétée, supprimez le port 22 :

```bash
sudo sed -i '/^ListenStream=22$/d' /etc/systemd/system/ssh.socket.d/listen.conf
sudo systemctl daemon-reload && sudo systemctl restart ssh.socket
sudo ufw delete allow 22/tcp          # si vous l'aviez ouvert
```

## Vérifier

```bash
ssh <SERVER_HOSTNAME>                                  # connexion par clé sur <SSH_PORT>
ssh -p 22 <SERVER_USER>@<SERVER_IP>                    # doit échouer (connection refused)
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password <SERVER_USER>@<SERVER_IP> -p <SSH_PORT>   # Permission denied
ssh root@<SERVER_IP> -p <SSH_PORT>                     # Permission denied
```

## Dépannage

| Symptôme | Solution |
|---|---|
| `Permission denied (publickey)` | Sur le serveur : `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` ; vérifiez avec `ssh -v <SERVER_HOSTNAME>` que la bonne clé est proposée ; assurez-vous d'avoir copié le fichier `.pub` |
| Le changement de port n'a aucun effet | `ss -tlnp` n'affiche toujours que 22 : le fichier complémentaire du socket n'a pas été appliqué ; relancez `daemon-reload` et `restart ssh.socket` |
| Connexion refusée sur le nouveau port | Pas d'écoute (`ss -tlnp`) ou port bloqué : `sudo ufw status`, `sudo journalctl -u ssh -n 50` |
| Enfermé dehors | Nécessite un accès à la console : corrigez `/etc/ssh/sshd_config.d/*` et le fichier complémentaire du socket, redémarrez `ssh.socket` |

Suite : [Pare-feu (UFW)](firewall-ufw.md)
