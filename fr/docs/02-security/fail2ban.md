# Fail2ban

Bannit les adresses IP qui échouent à répétition à se connecter en SSH, en ajoutant des règles temporaires au pare-feu. Complète la connexion par clé uniquement ([Renforcement de SSH](ssh-hardening.md)) ; installez-le une fois que SSH utilise `<SSH_PORT>`.

## 1. Installer

```bash
sudo apt update && sudo apt install fail2ban -y
```

## 2. Configurer la jail sshd

Ne modifiez pas `jail.conf` : les mises à jour du paquet l'écrasent. Placez vos paramètres dans `jail.local` (ou dans un fichier de `jail.d/`), qui remplace `jail.conf`.

```bash
sudo tee /etc/fail2ban/jail.local >/dev/null <<'CONF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 3
backend  = systemd
ignoreip = 127.0.0.1/8 ::1 192.168.1.0/24

[sshd]
enabled = true
port    = <SSH_PORT>
CONF
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban
```

| Paramètre | Signification |
|---|---|
| `maxretry` | Nombre de tentatives échouées dans `findtime` avant un bannissement |
| `findtime` | Fenêtre pendant laquelle les échecs sont comptés |
| `bantime` | Durée du bannissement (`-1` = permanent ; `bantime.increment = true` fait attendre plus longtemps les récidivistes) |
| `ignoreip` | Jamais banni : loopback et votre LAN. Adaptez le sous-réseau, et ajoutez votre propre IP publique fixe si vous en avez une |
| `backend = systemd` | Lit le journal systemd (fonctionne même si `/var/log/auth.log` est absent) |

`port` doit correspondre au port SSH réel. Avec le port 22 par défaut, la jail surveillerait le journal mais bannirait le mauvais port.

## 3. Exploitation

```bash
sudo fail2ban-client status                 # liste des jails
sudo fail2ban-client status sshd            # IP bannies et compteurs
sudo fail2ban-client set sshd unbanip 203.0.113.50
sudo fail2ban-client set sshd banip 203.0.113.50
sudo tail -f /var/log/fail2ban.log
```

> **Avertissement :** tester la jail depuis votre propre portable avec de mauvaises clés bannira votre propre IP (sauf si elle figure dans `ignoreip`). Débannissez-la par un autre chemin ou depuis la console.

## 4. Mises à jour de sécurité automatiques

`unattended-upgrades` installe les correctifs de sécurité sans intervention manuelle. Il est généralement préinstallé sur Ubuntu Server :

```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades     # répondre Yes
```

Les paramètres se trouvent dans `/etc/apt/apt.conf.d/50unattended-upgrades` (l'origine sécurité est activée par défaut). Le redémarrage automatique est désactivé par défaut ; ne l'activez que si une courte interruption à heure fixe est acceptable :

```
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
```

Sur un nœud K3s, un redémarrage relance tous les pods ; la valeur par défaut (pas de redémarrage automatique, redémarrage manuel après les mises à jour du noyau) est donc généralement préférable.

## Vérifier

```bash
sudo fail2ban-client status sshd
```

La sortie attendue contient `Journal matches: _SYSTEMD_UNIT=ssh.service + _COMM=sshd` (ou `sshd.service`) et `Currently banned: 0`. Simulation : depuis un appareil absent de `ignoreip`, échouez 3 fois à vous connecter avec une mauvaise clé/utilisateur, puis `status sshd` liste l'IP. Vérifiez les mises à jour :

```bash
sudo unattended-upgrade --dry-run --debug | tail -5
systemctl status unattended-upgrades --no-pager | head -5
```

## Dépannage

| Symptôme | Solution |
|---|---|
| Échecs de connexion visibles mais aucun bannissement | `port` incorrect ; mauvais `backend` ; lisez `/var/log/fail2ban.log` |
| `Journal matches` vide | `backend = systemd` manquant, ou le nom de l'unité SSH diffère : `systemctl list-units | grep ssh` |
| Vous vous êtes banni vous-même | `sudo fail2ban-client set sshd unbanip <IP>` depuis la console ou un autre réseau |

Suite : [Installation de Docker](../03-containers-and-k3s/docker-install.md)
