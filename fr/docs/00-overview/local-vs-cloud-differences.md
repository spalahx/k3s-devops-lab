# Différences entre local et cloud

La même pile fonctionne sur un mini-PC à domicile ou sur un VPS dans le cloud. Cette page liste les différences et les étapes à ignorer ou à adapter.

## Comparaison

| Aspect | Mini-PC à domicile | VPS cloud |
|---|---|---|
| Installation de l'OS | Clé USB, installeur sur la console | Choisir l'image Ubuntu Server LTS dans le panneau du fournisseur |
| Adresse | Adresse LAN fournie par le routeur ; nécessite une réservation DHCP ou une configuration netplan statique | IP publique statique attribuée par le fournisseur |
| Routeur | Requis : réservation, éventuellement redirection de ports | Aucun |
| Pare-feu | UFW sur l'hôte ; le NAT du routeur ajoute une couche | UFW sur l'hôte plus le pare-feu cloud du fournisseur (ouvrez les mêmes ports dans les deux) |
| Wi-Fi | Possible, mais préférez l'Ethernet | Sans objet |
| Accès | Directement depuis le LAN ; depuis l'extérieur uniquement via une passerelle VPS ou une redirection de ports | Direct via Internet, SSH par clé uniquement |
| DNS et domaines | Entrées `/etc/hosts` ou DNS local (noms `*.local`) | Vrais enregistrements DNS A pointant vers l'IP du VPS ; certificats TLS possibles |
| Énergie et coût | Achat du matériel, électricité, onduleur optionnel ; fonctionne 24h/24 à faible consommation | Abonnement mensuel selon CPU/RAM ; pas de matériel |
| Risque d'exposition | Faible tant que des ports ne sont pas redirigés | Élevé dès la première minute : des robots scannent les nouvelles IP, sécurisez avant toute autre chose |
| Ressources | Fixées par votre matériel | Redimensionnables |

## Quoi ignorer ou adapter

| Doc | Mini-PC local | VPS cloud |
|---|---|---|
| [Installer Ubuntu Server](../01-os-and-network/install-ubuntu-server.md) | À suivre en entier | Ignorez l'installeur ; faites les mises à jour post-installation, la langue et le fuseau horaire |
| [IP statique et réseau](../01-os-and-network/static-ip-and-networking.md) | À suivre en entier | À ignorer ; le fournisseur fixe déjà l'IP |
| [Sécurité](../02-security/ssh-hardening.md) | À suivre en entier | À suivre en entier, dès la première chose après la connexion ; reproduisez les règles UFW dans le pare-feu cloud |
| [Docker](../03-containers-and-k3s/docker-install.md), [K3s](../03-containers-and-k3s/k3s-install.md) | À suivre | À suivre |
| [Ingress et première application](../03-containers-and-k3s/ingress-traefik-first-app.md) | Noms dans le fichier hosts | Utilisez de vrais enregistrements DNS à la place des entrées du fichier hosts |
| [Passerelle VPS](../06-remote-access/vps-gateway-setup.md), [tunnel inverse](../06-remote-access/reverse-ssh-tunnel-systemd.md), [ProxyJump](../06-remote-access/proxyjump-client-config.md) | Nécessaires pour l'accès depuis l'extérieur du LAN | À ignorer, sauf ProxyJump si vous ajoutez un nœud privé derrière le VPS |
| [Supervision](../08-monitoring/helm-basics.md) | À suivre | À suivre ; surveillez la mémoire sur les petites offres |
| [Samba](../09-optional-extras/samba-file-storage.md) | LAN uniquement | N'exposez pas SMB sur Internet ; ignorez ou tunnelisez via SSH |
| [Dépannage réseau](../99-appendix/troubleshooting-networking.md) | S'applique | Sans objet |

> **Avertissement :** sur un VPS, ne fermez pas votre unique session SSH pendant que vous modifiez le port SSH ou les règles UFW. Ouvrez une seconde session et testez les nouveaux paramètres avant de vous déconnecter ; la récupération passe par la console web du fournisseur.

Suite : [Installation de l'OS](../01-os-and-network/install-ubuntu-server.md)
