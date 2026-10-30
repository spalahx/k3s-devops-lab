# Configuration de la passerelle VPS

Prépare un petit VPS loué avec une IP publique fixe, servant de point de rendez-vous pour un serveur domestique derrière un NAT ou une IP dynamique. Ignorez cette étape si le serveur dispose déjà d'une IP publique fixe (par exemple un VPS cloud), ou si vous préférez un VPN tel que WireGuard/Tailscale.

Principe : le serveur domestique ouvre une connexion SSH sortante vers le VPS et y publie son propre port SSH (`ssh -R`). Les clients se connectent au VPS, qui retransmet le trafic via cette connexion. Aucune redirection de port sur le routeur n'est nécessaire, et l'IP domestique peut changer.

Espaces réservés utilisés ici (en plus des espaces réservés standard) :

| Espace réservé | Signification |
|---|---|
| `<VPS_USER>` | Utilisateur administrateur sur le VPS (non root, sudo) |
| `<TUNNEL_USER>` | Utilisateur sans privilèges sur le VPS qui ne fait que porter le tunnel |
| `<TUNNEL_PORT>` | Port sur le loopback du VPS qui correspond au SSH du serveur domestique (par ex. `2222`) |

## 1. Louer le VPS

- N'importe quel fournisseur convient ; l'offre la plus petite (1 vCPU / 1 Go de RAM) suffit, puisqu'il ne fait que relayer SSH.
- Choisissez la même Ubuntu Server LTS que le serveur domestique.
- Notez l'IP publique (`<VPS_IP>`) et l'identifiant de connexion initial.

## 2. Créer un utilisateur administrateur et durcir

```bash
ssh root@<VPS_IP>
adduser <VPS_USER>
usermod -aG sudo <VPS_USER>
```

Depuis le portable, installez une clé et vérifiez la connexion avant de toucher à quoi que ce soit d'autre :

```bash
ssh-copy-id <VPS_USER>@<VPS_IP>
ssh <VPS_USER>@<VPS_IP>
```

Appliquez ensuite la même base que sur le serveur domestique : [durcissement SSH](../02-security/ssh-hardening.md), [UFW](../02-security/firewall-ufw.md), [Fail2ban](../02-security/fail2ban.md). Le VPS est directement exposé à Internet, ce n'est donc pas optionnel. Ouvrez uniquement le port SSH :

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow <SSH_PORT>/tcp
sudo ufw enable
```

> **Avertissement :** gardez une seconde session ouverte pendant que vous modifiez les paramètres SSH ou les règles du pare-feu, et autorisez le port SSH avant d'activer UFW.

## 3. Créer l'utilisateur du tunnel

Un utilisateur dédié limite les dégâts si le serveur domestique (ou sa clé) est compromis.

```bash
sudo adduser --disabled-password --gecos "" --shell /usr/sbin/nologin <TUNNEL_USER>
sudo install -d -m 700 -o <TUNNEL_USER> -g <TUNNEL_USER> /home/<TUNNEL_USER>/.ssh
```

Le shell `nologin` convient : `ssh -N -R` n'a pas besoin de shell.

## 4. Créer la clé du tunnel sur le serveur domestique

Une clé distincte, pas celle utilisée pour Git :

```bash
ssh-keygen -t ed25519 -C "home-to-vps-tunnel" -f ~/.ssh/id_ed25519_tunnel -N ""
cat ~/.ssh/id_ed25519_tunnel.pub
```

Aucune phrase secrète n'est définie car le service systemd doit démarrer sans intervention. Compensez en restreignant la clé côté VPS.

Sur le VPS, ajoutez la clé publique à `/home/<TUNNEL_USER>/.ssh/authorized_keys` sur une seule ligne avec des restrictions :

```
restrict,port-forwarding,permitlisten="127.0.0.1:<TUNNEL_PORT>" ssh-ed25519 AAAA...key... home-to-vps-tunnel
```

```bash
sudo chown <TUNNEL_USER>:<TUNNEL_USER> /home/<TUNNEL_USER>/.ssh/authorized_keys
sudo chmod 600 /home/<TUNNEL_USER>/.ssh/authorized_keys
```

| Option | Effet |
|---|---|
| `restrict` | Désactive le PTY, la redirection d'agent/X11 et l'exécution de commandes |
| `port-forwarding` | Réactive uniquement la redirection de ports |
| `permitlisten` | La clé ne peut ouvrir que cette unique écoute sur le VPS |

## 5. Paramètres sshd sur le VPS

Vérifiez les valeurs effectives :

```bash
sudo sshd -T | grep -Ei 'allowtcpforwarding|gatewayports'
```

| Paramètre | Valeur | Quand |
|---|---|---|
| `AllowTcpForwarding` | `yes` (par défaut) | Requis pour `-R` |
| `GatewayPorts` | `no` (par défaut) | Recommandé. Le port du tunnel écoute uniquement sur `127.0.0.1` du VPS, et les clients l'atteignent via [ProxyJump](proxyjump-client-config.md) |
| `GatewayPorts` | `clientspecified` ou `yes` | Uniquement si des tiers doivent se connecter directement à `<VPS_IP>:<TUNNEL_PORT>` |

Si un accès direct externe est vraiment nécessaire, modifiez `/etc/ssh/sshd_config` (ou un fichier dans `/etc/ssh/sshd_config.d/`) :

```
GatewayPorts clientspecified
```

```bash
sudo sshd -t && sudo systemctl restart ssh
```

Avec `clientspecified`, le côté tunnel doit utiliser `-R 0.0.0.0:<TUNNEL_PORT>:localhost:<SSH_PORT>`, et la valeur `permitlisten` dans `authorized_keys` doit correspondre à cette adresse. Restreignez ensuite le port dans UFW :

```bash
sudo ufw allow from 203.0.113.50 to any port <TUNNEL_PORT> proto tcp
```

> **Avertissement :** un port de tunnel accessible publiquement expose le SSH du serveur domestique aux attaques par force brute. Exigez une connexion par clé uniquement sur le serveur domestique et limitez les IP sources dans UFW.

## Vérification

```bash
# Depuis le serveur domestique : la connexion par clé fonctionne (l'utilisateur du tunnel n'a pas de shell, attendez-vous donc à une session fermée)
ssh -i ~/.ssh/id_ed25519_tunnel <TUNNEL_USER>@<VPS_IP> -p <SSH_PORT>
# Sur le VPS : la configuration sshd est valide et le pare-feu est actif
sudo sshd -t && sudo ufw status
```

Suite : [Tunnel SSH inverse en tant que service systemd](reverse-ssh-tunnel-systemd.md)
