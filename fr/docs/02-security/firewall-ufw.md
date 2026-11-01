# Pare-feu (UFW)

Bloque tout le trafic entrant sauf SSH et les ports web grâce à UFW (Uncomplicated Firewall, une interface pour iptables/nftables). Configurez-le avant de changer le port SSH et avant d'installer K3s, car K3s ajoute ses propres règles et certaines combinaisons cassent le réseau des pods.

> **Avertissement :** `ufw enable` sans règle SSH coupe votre session. Ajoutez d'abord la règle SSH et gardez une seconde session ouverte.

## 1. Valeurs par défaut

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

## 2. Autoriser SSH (avant l'activation)

Utilisez le port sur lequel sshd écoute actuellement. Pendant la migration de port, autorisez les deux :

```bash
sudo ufw allow 22/tcp comment 'SSH (temporary)'
sudo ufw allow <SSH_PORT>/tcp comment 'SSH'
```

Optionnel, SSH limité au LAN (adaptez le sous-réseau ; c'est plus strict et sûr pour un serveur domestique) :

```bash
sudo ufw allow from 192.168.1.0/24 to any port <SSH_PORT> proto tcp comment 'SSH from LAN'
```

Pour un serveur avec une IP publique, restreignez SSH à des adresses connues dans la mesure du possible, par exemple `sudo ufw allow from 203.0.113.10 to any port <SSH_PORT> proto tcp`.

## 3. Ports web

Traefik (l'ingress controller de K3s) sert le HTTP/HTTPS sur le nœud :

```bash
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
```

Variante limitée au LAN (elle restreint les services de l'hôte lui-même, mais pas Traefik ; voir la note ci-dessous) :

```bash
sudo ufw allow from 192.168.1.0/24 to any port 80 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 443 proto tcp
```

> **Note :** les règles UFW pour 80/443 ne contrôlent **pas** l'accès à Traefik. K3s publie ces ports par DNAT dans la table NAT et transmet le trafic au pod Traefik : il passe donc par FORWARD, et les chaînes de K3s sont placées avant celles d'UFW. Sur le serveur de référence (K3s v1.36, UFW avec deny incoming et deny routed, sans règle pour le port 80), Traefik répondait depuis un autre hôte du LAN. Pour limiter l'accès à Traefik, utilisez le pare-feu du routeur (ou le groupe de sécurité dans le cloud), pas UFW.

## 4. Règles K3s

Sur un cluster à nœud unique, seuls 80/443 sont nécessaires depuis l'extérieur. Les pods et services communiquent via les interfaces du nœud (`cni0`, `flannel.1`), et la politique par défaut d'UFW peut bloquer ce trafic. Sur le serveur de référence, le cluster fonctionnait sans règle pour les réseaux des pods et des services, car K3s place ses chaînes de transfert avant celles d'UFW. Les deux règles ci-dessous sont conservées comme solution de repli : ajoutez-les si les pods perdent le DNS ou l'accès à Internet après `ufw enable`. CIDR par défaut :

```bash
sudo ufw allow from 10.42.0.0/16 to any comment 'K3s pods'
sudo ufw allow from 10.43.0.0/16 to any comment 'K3s services'
```

Uniquement si vous utilisez l'API Kubernetes ou kubectl depuis une autre machine, ou si vous ajoutez des nœuds :

| Port | Proto | Rôle | Ouvert à |
|---|---|---|---|
| 6443 | tcp | API Kubernetes | portable / nœuds agents uniquement |
| 10250 | tcp | métriques du kubelet | autres nœuds uniquement |
| 8472 | udp | flannel VXLAN | autres nœuds uniquement |

```bash
sudo ufw allow from 192.168.1.0/24 to any port 6443 proto tcp comment 'K3s API from LAN'
```

## 5. Activer et vérifier

```bash
sudo ufw enable
sudo ufw status numbered
sudo ufw status verbose
```

Attendu : `Status: active`, `Default: deny (incoming), allow (outgoing)`, des règles pour `<SSH_PORT>`, 80, 443. Lorsque la migration du port SSH est terminée, supprimez la règle du port 22 :

```bash
sudo ufw status numbered
sudo ufw delete allow 22/tcp
```

Supprimez par le texte de la règle, ou par son numéro dans `status numbered` (les numéros se décalent après chaque suppression).

## Pièges

- **Docker contourne UFW.** Les ports publiés avec `docker run -p 8080:80` sont insérés dans iptables avant UFW, donc `ufw deny` ne les masque pas. Liez-les à localhost (`-p 127.0.0.1:8080:80`) ou ne publiez pas le port.
- **K3s ajoute ses propres règles iptables** (équilibreur de charge de service pour Traefik, NAT de kube-proxy). Les ports 80/443 atteignent Traefik par DNAT dans le chemin forward, indépendamment des règles d'entrée d'UFW. Si, après l'activation d'UFW, les sites expirent alors que `curl localhost` fonctionne sur le serveur, ajoutez les règles CIDR pods/services ci-dessus et, si besoin, définissez `DEFAULT_FORWARD_POLICY="ACCEPT"` dans `/etc/default/ufw`, puis `sudo ufw reload`. Le serveur de référence fonctionnait avec `DROP` et sans règle supplémentaire.
- **Les pods ne résolvent plus le DNS / n'atteignent plus Internet après `ufw enable` :** la règle du CIDR des pods ci-dessus est absente. `kubectl run -it --rm t --image=busybox --restart=Never -- nslookup kubernetes.default` est un test rapide.
- **L'ordre compte :** `ufw allow` avant `ufw enable`, et la règle du port SSH avant de changer le port SSH.
- **D'autres services ont besoin de leurs propres règles :** par exemple `sudo ufw allow samba` ([Samba](../09-optional-extras/samba-file-storage.md)), limité au sous-réseau du LAN.
- Si K3s se comporte encore mal et que la machine n'est joignable que depuis un LAN de confiance, la solution de repli de la documentation K3s est de désactiver UFW (`sudo ufw disable`) et de s'appuyer sur le pare-feu du routeur. Préférez les règles ci-dessus sur tout serveur ayant une IP publique.

## Vérifier

```bash
sudo ufw status verbose
sudo ss -tlnp | grep -E ":<SSH_PORT>|:80 |:443 "
```

Depuis le portable : `ssh <SERVER_HOSTNAME>` fonctionne ; `nc -zv <SERVER_IP> 3306` (un port fermé) expire. Une fois K3s installé, `kubectl get pods -A` doit afficher uniquement des Pods `Running`.

Suite : [Fail2ban](fail2ban.md)
