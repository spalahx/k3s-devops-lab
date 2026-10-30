# Dépannage réseau (matériel local uniquement)

Diagnostic d'un adaptateur réseau absent ou instable, le plus souvent Wi-Fi, sur une machine physique. Ne s'applique pas à un VPS. Si le serveur dispose d'Ethernet, utilisez-le et ignorez complètement le Wi-Fi.

Suivez les étapes dans l'ordre ; arrêtez-vous à la première qui explique le symptôme.

## 1. L'interface est-elle présente ?

```bash
ip link
ip -br addr
```

Attendez-vous à `lo`, un nom Ethernet tel que `enp2s0` et, pour le Wi-Fi, une entrée `wlan0`/`wlp*`. Les interfaces virtuelles `cni0`, `flannel.1`, `veth*`, `docker0` appartiennent aux conteneurs et ne disent rien des adaptateurs physiques.

## 2. Est-elle bloquée par logiciel ?

```bash
rfkill list
sudo rfkill unblock wifi
```

`Soft blocked: yes` se corrige avec le unblock. Si l'adaptateur est aussi absent de `rfkill list`, le problème est plus profond (pilote).

## 3. Le matériel existe-t-il sur le bus ?

```bash
lspci -nn | grep -iE 'network|wireless|wifi|ethernet'
lsusb
```

| Résultat | Signification |
|---|---|
| Périphérique listé avec l'ID `[vendor:device]` | Le matériel est correct ; le pilote est manquant ou défaillant. Notez l'ID |
| Non listé | Problème physique : réenfichez la carte M.2, vérifiez les réglages du BIOS (adaptateur désactivé), essayez un autre port USB |

## 4. Pilote et firmware

```bash
lspci -nnk | grep -iA3 'network'      # ligne "Kernel driver in use:"
sudo dmesg | grep -iE 'firmware|wlan|wifi|iwlwifi|ath|rtw|mt79|r8169|e1000|enp'
uname -r
```

- Pas de ligne `Kernel driver in use` : aucun pilote n'est associé au périphérique.
- `firmware: failed to load` ou `-2` : installez le firmware, puis redémarrez.

```bash
sudo apt update
sudo apt install --reinstall linux-firmware
```

- Vérifiez si un module de pilote couvre votre ID (`modinfo <module> | grep -i alias`, recherchez la partie device de l'ID).
- Les puces récentes ne sont souvent prises en charge que par des noyaux plus récents. Mettez d'abord le système à jour ; sur une version LTS, installez le noyau HWE :

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install linux-generic-hwe-$(lsb_release -rs)
sudo reboot
```

- Forcer un ID non pris en charge sur un pilote voisin via `new_id` échoue généralement avec `Invalid argument` lorsque la puce diffère en interne ; ne comptez pas dessus :

```bash
echo "<vendor> <device>" | sudo tee /sys/bus/pci/drivers/<module>/new_id
```

> **Avertissement :** Un pilote hors arbre compilé à la main casse silencieusement à la prochaine mise à jour du noyau, et le serveur sans écran disparaît du réseau. K3s réagit aux blocages réseau en redémarrant les Pods. Pour un serveur, préférez Ethernet, ou un adaptateur Wi-Fi USB dont la puce est prise en charge par le pilote du noyau.

## 5. Configuration netplan

Les noms d'interface dans netplan doivent correspondre à `ip link`. Les fichiers se trouvent dans `/etc/netplan/`.

```yaml
# /etc/netplan/50-wifi.yaml  (exemple Wi-Fi, mode 600)
network:
  version: 2
  renderer: networkd
  wifis:
    wlan0:
      dhcp4: true
      access-points:
        "<WIFI_SSID>":
          password: "<WIFI_PASSWORD>"
```

```bash
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan try        # revient en arrière après 120 s si la connectivité est perdue
sudo netplan apply
```

`wpasupplicant` doit être installé pour le Wi-Fi (`sudo apt install wpasupplicant`). `<WIFI_SSID>` et `<WIFI_PASSWORD>` sont le nom et la clé de votre réseau. Adressage statique : [IP statique et réseau](../01-os-and-network/static-ip-and-networking.md).

## 6. Économie d'énergie Wi-Fi

Symptômes : latence élevée, SSH qui se fige après une période d'inactivité. Vérifiez et désactivez :

```bash
iw dev wlan0 get power_save
sudo iw dev wlan0 set power_save off
```

Pour le rendre persistant, créez `/etc/NetworkManager/conf.d/wifi-powersave.conf` avec `[connection]` et `wifi.powersave = 2` si NetworkManager est utilisé. Avec networkd, utilisez une unité systemd ou une règle udev qui exécute la commande `iw` ci-dessus au démarrage.

## 7. DNS et routage

Connecté mais les noms ne se résolvent pas :

```bash
ip route                         # une route par défaut existe ?
ping -c2 1.1.1.1                 # connectivité IP
ping -c2 example.com             # résolution de noms
resolvectl status                # serveurs DNS par lien
```

- L'IP fonctionne, pas les noms : définissez `nameservers: addresses: [1.1.1.1, 8.8.8.8]` dans netplan et appliquez.
- Pas de route par défaut : passerelle incorrecte dans la configuration statique.
- Deux routes par défaut (Ethernet et Wi-Fi actifs) : définissez `dhcp4-overrides: {route-metric: 600}` sur l'interface secondaire.

## 8. Dernier recours

- Le réseau a disparu après une mise à jour du noyau : démarrez un noyau plus ancien depuis le menu « Advanced options » de GRUB, ou branchez Ethernet.
- Vérifiez le câble, le port du switch et la table des baux DHCP du routeur avant d'incriminer les pilotes.

Suivant : [Glossaire](glossary.md)
