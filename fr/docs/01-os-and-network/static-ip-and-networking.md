# IP statique et réseau

Donne au serveur une adresse stable, un nom d'hôte et une horloge correcte, et fait en sorte que les noms `*.<DOMAIN_BASE>` soient résolus sur le portable. Une IP qui change casse les alias SSH, les entrées hosts et tous les services qui pointent vers le serveur ; faites donc cette étape avant de construire quoi que ce soit par-dessus.

## 1. Trouver l'interface

```bash
ip -br a            # nom de l'interface et adresse actuelle
ip route | grep default   # adresse de la passerelle (routeur)
resolvectl status | grep -A2 "Link"   # serveurs DNS actuels
```

Valeurs d'exemple utilisées ci-dessous : interface `enp1s0`, serveur `192.168.1.150`, routeur `192.168.1.1`. Remplacez-les par les vôtres (`<SERVER_IP>` est l'adresse que vous choisissez).

## 2. Option A : réservation DHCP sur le routeur (la plus simple)

Dans la page d'administration du routeur (section DHCP / LAN), associez l'adresse MAC du serveur à l'IP souhaitée. L'adresse MAC s'affiche avec :

```bash
ip link show enp1s0 | grep link/ether
```

Rien ne change sur le serveur. Le nom de la fonctionnalité varie : réservation DHCP, DHCP statique, réservation d'adresse. Redémarrez le serveur (ou renouvelez le bail) pour récupérer l'adresse.

## 3. Option B : IP statique avec netplan

Netplan est la couche de configuration réseau d'Ubuntu (fichiers YAML dans `/etc/netplan/`). Choisissez une adresse en dehors de la plage DHCP du routeur.

```bash
ls /etc/netplan/
sudo cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak
sudo nano /etc/netplan/50-cloud-init.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: false
      addresses:
        - <SERVER_IP>/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

- L'indentation se fait uniquement avec des espaces, 2 par niveau. Une tabulation ou une mauvaise indentation rend le fichier invalide.
- `routes: to: default` remplace `gateway4`, désormais obsolète.
- Les fichiers netplan ne doivent pas être lisibles par tous : `sudo chmod 600 /etc/netplan/*.yaml`.
- Le nom du fichier peut différer (`00-installer-config.yaml`) ; modifiez celui qui existe.

Appliquez avec retour arrière automatique, pour qu'une erreur ne vous enferme pas dehors :

```bash
sudo netplan try        # appuyez sur Entrée dans les 120 s pour conserver, sinon retour à l'état précédent
sudo netplan apply
```

> **Avertissement :** lancez `netplan try` depuis la console ou depuis une session SSH que vous pouvez vous permettre de perdre. Si vous avez changé l'IP, la session SSH en cours est coupée ; reconnectez-vous à la nouvelle adresse.

## 4. Nom d'hôte et fuseau horaire

```bash
sudo hostnamectl set-hostname <SERVER_HOSTNAME>
sudo timedatectl set-timezone Europe/Berlin     # utilisez votre fuseau : timedatectl list-timezones
timedatectl set-ntp true
```

Si `/etc/hosts` contient une ligne `127.0.1.1` avec l'ancien nom d'hôte, remplacez-le par `<SERVER_HOSTNAME>`.

## 5. Résolution de noms sur le serveur

```bash
resolvectl query ubuntu.com
ping -c2 1.1.1.1 && ping -c2 ubuntu.com
```

Si l'IP répond mais pas le nom, le DNS est défaillant : revérifiez `nameservers` dans le fichier netplan.

## 6. Résolution de `*.<DOMAIN_BASE>` sur le portable

Les projets sont accessibles par des noms d'hôte tels que `<PROJECT_NAME>.<DOMAIN_BASE>`, que Traefik route selon l'en-tête `Host`. Sur un LAN privé, aucun enregistrement DNS public n'existe ; le portable doit donc associer les noms à `<SERVER_IP>`.

| Méthode | Quand | Comment |
|---|---|---|
| Fichier `hosts` | Quelques projets, un seul portable | Une ligne par nom, ci-dessous |
| DNS local (routeur ou `dnsmasq`) | Nombreux noms ou nombreux appareils | Joker `address=/<DOMAIN_BASE>/<SERVER_IP>` |
| Enregistrement DNS A public | Serveur cloud avec IP publique | Voir [Différences entre local et cloud](../00-overview/local-vs-cloud-differences.md) |

Emplacement du fichier `hosts` : macOS/Linux `/etc/hosts` (à modifier avec `sudo`).

```bash
echo "<SERVER_IP>  <PROJECT_NAME>.<DOMAIN_BASE> phpmyadmin.<PROJECT_NAME>.<DOMAIN_BASE>" | sudo tee -a /etc/hosts
# macOS uniquement : vider le cache DNS
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

- Le format est strict : l'IP, puis les noms séparés par des espaces, sur une seule ligne. Pas de `http://`, pas de barre oblique finale.
- Un fichier `hosts` ne prend pas en charge les jokers ; chaque nom doit être listé.
- Évitez le suffixe `.local` pour `<DOMAIN_BASE>` sur macOS/Linux : il est réservé à mDNS et peut se résoudre lentement, voire pas du tout. Préférez quelque chose comme `.lab` ou `.home.arpa`.

DNS joker local avec `dnsmasq` (sur le serveur ou sur tout hôte du LAN toujours allumé), si vous le préférez à `hosts` :

```bash
sudo apt install dnsmasq -y
echo "address=/<DOMAIN_BASE>/<SERVER_IP>" | sudo tee /etc/dnsmasq.d/lab.conf
sudo systemctl restart dnsmasq
```

Définissez ensuite cet hôte comme serveur DNS sur le routeur ou le portable. Sur une machine exécutant `systemd-resolved` (valeur par défaut d'Ubuntu), le port 53 est occupé par le résolveur stub ; définissez d'abord `DNSStubListener=no` dans `/etc/systemd/resolved.conf`, ou exécutez dnsmasq sur un autre hôte.

## Wi-Fi

Utilisez l'Ethernet pour un nœud K3s. Les contrôles de santé de Kubernetes considèrent un court blocage du Wi-Fi comme une panne du nœud et les pods redémarrent de façon aléatoire. Certaines puces Wi-Fi n'ont aucun pilote dans le noyau principal. Si le Wi-Fi est la seule option, ou si la puce n'est pas détectée, consultez [Dépannage réseau](../99-appendix/troubleshooting-networking.md) ; un adaptateur Wi-Fi USB avec un chipset pris en charge de longue date est la solution de repli fiable.

## Vérifier

```bash
ip -br a                       # <SERVER_IP> sur l'interface
ip route | grep default
hostnamectl                    # nom d'hôte, fuseau horaire via : timedatectl
ping -c2 ubuntu.com
```

Depuis le portable :

```bash
ping -c2 <SERVER_IP>
ping -c2 <PROJECT_NAME>.<DOMAIN_BASE>     # se résout vers <SERVER_IP>
ssh <SERVER_USER>@<SERVER_IP>
```

Redémarrez une fois (`sudo reboot`) et vérifiez que l'adresse reste la même.

Suite : [Renforcement de SSH](../02-security/ssh-hardening.md)
