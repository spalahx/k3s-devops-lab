# Installer Ubuntu Server

Installe Ubuntu Server LTS sur une machine vierge à partir d'une clé USB. Ignorez cette étape si la machine est un VPS cloud livré avec Ubuntu (voir [Différences entre local et cloud](../00-overview/local-vs-cloud-differences.md)).

## 1. Choisir l'image

| Choix | Valeur |
|---|---|
| Distribution | Ubuntu Server (sans bureau), dernière LTS (par exemple 24.04 LTS ; LTS = 5 ans de mises à jour de sécurité) |
| Architecture | `amd64` pour les machines Intel/AMD, `arm64` pour les cartes ARM. Une mauvaise architecture ne démarre pas |
| Téléchargement | `https://ubuntu.com/download/server` (l'ISO fait environ 2 Go) |

Vérifiez le téléchargement avec la somme SHA256 publiée :

```bash
# macOS
shasum -a 256 ~/Downloads/ubuntu-*-live-server-amd64.iso
# Linux
sha256sum ~/Downloads/ubuntu-*-live-server-amd64.iso
```

## 2. Écrire la clé USB

Utilisez une clé de 8 Go ou plus. Tout son contenu est effacé.

### macOS

```bash
diskutil list                         # repérer la clé par sa taille, p. ex. /dev/disk4 (external, physical)
diskutil unmountDisk /dev/diskN
sudo dd if=~/Downloads/ubuntu-XX.XX-live-server-amd64.iso of=/dev/rdiskN bs=1m status=progress
diskutil eject /dev/diskN
```

### Linux

```bash
lsblk                                 # repérer la clé, p. ex. /dev/sdb (pas une partition comme sdb1)
sudo umount /dev/sdb* 2>/dev/null
sudo dd if=~/Downloads/ubuntu-XX.XX-live-server-amd64.iso of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

- `rdiskN` sous macOS est le périphérique brut et écrit beaucoup plus vite que `diskN`.
- `dd` ne demande aucune confirmation. Une mauvaise cible `of=` (par exemple le disque interne `disk0`) détruit ce disque. Vérifiez deux fois la taille dans `diskutil list` / `lsblk`.
- `Resource busy` sous macOS signifie que la clé est encore montée : relancez `diskutil unmountDisk`.

## 3. Démarrer la machine depuis la clé USB

1. Connectez la machine au routeur avec un câble Ethernet. Utilisez le réseau filaire pour l'installation : l'installeur télécharge des paquets, et certaines puces Wi-Fi n'ont pas de pilote dans l'installeur (voir [Dépannage réseau](../99-appendix/troubleshooting-networking.md)).
2. Branchez un écran et un clavier (nécessaires seulement jusqu'à ce que SSH fonctionne).
3. Insérez la clé, allumez la machine et appuyez plusieurs fois sur la touche du menu de démarrage (généralement `F7`, `F10`, `F11`, `F12`, `Échap` ou `Suppr` ; dépend du fabricant).
4. Choisissez l'entrée qui commence par `UEFI:` et nomme la clé. Ne choisissez pas `Legacy`.

Si la clé n'apparaît pas : utilisez un autre port USB (préférez un port USB 2.0), réécrivez la clé avec un autre outil et vérifiez que Secure Boot ne la bloque pas (l'ISO Ubuntu est signée et démarre normalement avec Secure Boot activé).

## 4. Choix de l'installeur

L'installeur est en mode texte : flèches, `Tab`, `Espace` (cocher/décocher), `Entrée`.

| Écran | Choix |
|---|---|
| Langue / clavier | Anglais (les messages d'erreur sont plus faciles à rechercher) |
| Type d'installation | `Ubuntu Server` (non minimisé) |
| Réseau | L'interface filaire doit afficher une adresse via DHCP. Laissez tel quel ; une IP statique sera définie plus tard ([IP statique](static-ip-and-networking.md)) |
| Proxy / miroir | Valeurs par défaut |
| Stockage | Utiliser un disque entier, laisser activée l'option « Set up this disk as an LVM group » (les partitions pourront être redimensionnées plus tard). Sélectionnez le disque interne, pas la clé USB |
| Profil | Votre nom, nom du serveur `<SERVER_HOSTNAME>`, nom d'utilisateur `<SERVER_USER>`, un mot de passe robuste (toujours nécessaire pour `sudo` une fois la connexion SSH par mot de passe désactivée) |
| Ubuntu Pro | Ignorer |
| SSH | **Cochez « Install OpenSSH server »**. N'importez pas de clés maintenant |
| Featured snaps | Ne rien sélectionner |

Attendez la fin de l'installation et des mises à jour (10 à 20 minutes), puis sélectionnez **Reboot**. Lorsque c'est demandé, **retirez la clé USB** avant d'appuyer sur `Entrée`, sinon la machine redémarre sur l'installeur.

> **Avertissement :** si OpenSSH server n'a pas été coché, installez-le à la console : `sudo apt install openssh-server`.

## 5. Première connexion et mise à jour

À la console, connectez-vous en tant que `<SERVER_USER>` (le mot de passe ne s'affiche pas pendant la saisie). Trouvez l'adresse :

```bash
ip -br a
```

Exemple : `enp1s0  UP  192.168.1.150/24`. Les noms d'interface (`enp1s0`, `eno1`, `eth0`) diffèrent selon la machine.

Travaillez maintenant depuis le portable ; l'écran et le clavier ne sont plus nécessaires :

```bash
ssh <SERVER_USER>@<SERVER_IP>
```

Répondez `yes` à la question sur l'empreinte de l'hôte lors de la première connexion (elle est enregistrée dans `~/.ssh/known_hosts` et vous avertit si l'hôte change par la suite). Puis mettez à jour :

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot        # si le noyau ou libc a été mis à jour
```

## Vérifier

```bash
lsb_release -d                       # Ubuntu LTS
systemctl is-active ssh              # active
ip -br a                             # l'interface filaire a une adresse
sudo apt update && apt list --upgradable   # plus rien (ou seulement des paquets retenus)
```

## Échecs courants

| Symptôme | Cause / solution |
|---|---|
| L'installeur n'affiche aucun réseau | Rebranchez le câble, essayez un autre câble/port, vérifiez que le routeur fournit le DHCP |
| `ssh: Connection timed out` | Mauvaise IP, ou le portable est sur un autre réseau ; revérifiez `ip -br a` sur le serveur |
| `ssh: Connection refused` | OpenSSH server non installé ou arrêté : `sudo apt install openssh-server && systemctl status ssh` |
| Mot de passe de l'utilisateur perdu | Nécessite un accès à la console et le mode de récupération GRUB, ou une réinstallation |

Suite : [IP statique et réseau](static-ip-and-networking.md)
