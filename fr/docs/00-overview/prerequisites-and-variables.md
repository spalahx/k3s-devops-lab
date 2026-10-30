# Prérequis et variables

Matériel, logiciels et comptes nécessaires avant de commencer, et chaque espace réservé utilisé dans la documentation. Remplacez les espaces réservés par vos propres valeurs lorsque vous copiez les commandes.

## Matériel

| Élément | Minimum | Confortable |
|---|---|---|
| CPU | 2 cœurs, x86_64 ou arm64 | 4 cœurs ou plus |
| RAM | 4 Go (K3s seul environ 1 Go) | 16 Go ou plus (plusieurs projets, supervision) |
| Disque | SSD de 40 Go | SSD de 250 Go ou plus |
| Réseau | Ethernet filaire | Ethernet filaire, routeur avec réservation DHCP |
| LLM locaux (optionnel) | 16 Go de RAM | 32 Go de RAM ou plus, ou un GPU compatible |

Préférez l'Ethernet au Wi-Fi pour un serveur (voir [Dépannage réseau](../99-appendix/troubleshooting-networking.md)).

## Logiciels et comptes

- Clé USB d'installation (8 Go ou plus) et un outil pour écrire l'ISO, pour du matériel local ; ou un VPS avec une image Ubuntu Server LTS.
- Portable avec un terminal et `ssh` (macOS ou Linux), plus un IDE prenant en charge Remote-SSH.
- Compte d'hébergement Git (GitHub ou GitLab) pour le code ; un par identité si vous séparez travail et personnel.
- Optionnel : VPS avec IP publique (accès distant), nom de domaine enregistré (sites publics), registre de conteneurs.

## Espaces réservés

| Espace réservé | Signification | Exemple |
|---|---|---|
| `<SERVER_USER>` | Utilisateur sudo non root sur le serveur | `dev` |
| `<SERVER_HOSTNAME>` | Nom d'hôte du serveur | `devbox` |
| `<SERVER_IP>` | Adresse du serveur sur le LAN (ou IP publique d'un VPS) | `192.168.1.50` |
| `<SSH_PORT>` | Port SSH personnalisé choisi lors du renforcement | `2222` |
| `<DOMAIN_BASE>` | Domaine de base ou suffixe local pour les noms d'hôte des projets | `devbox.local`, `example.com` |
| `<PROJECT_NAME>` | Nom de projet court en minuscules, utilisé pour le dossier, le namespace et le nom d'hôte | `blog` |
| `<VPS_IP>` | IP publique du VPS passerelle | `203.0.113.10` |
| `<GIT_WORK_EMAIL>` | E-mail pour les commits professionnels | `me@work.example` |
| `<GIT_PERSONAL_EMAIL>` | E-mail pour les commits personnels | `me@home.example` |
| `<DB_PASSWORD>` | Mot de passe de base de données que vous générez (`openssl rand -base64 24`) | non stocké dans le dépôt |
| `<PROJECT_GROUP>` | Répertoire regroupant les projets (entreprise, client, `personal`) | `personal` |
| `<DB_NAME>` | Nom de la base de données | `wordpress` |
| `<OLD_DOMAIN>` | Domaine d'un site en cours de migration | `old.example.com` |
| `<GIT_USER_NAME>` | Nom pour les commits Git | `Jane Doe` |
| `<ORG>`, `<REPO>` | Organisation/utilisateur Git et nom du dépôt | `acme`, `blog` |
| `<VPS_USER>` | Utilisateur administrateur sur le VPS passerelle | `admin` |
| `<TUNNEL_USER>`, `<TUNNEL_PORT>` | Utilisateur restreint sur le VPS et port sur lequel le tunnel écoute | `tunnel`, `2200` |
| `<GRAFANA_ADMIN_PASSWORD>`, `<SAMBA_PASSWORD>` | Mots de passe que vous générez | non stockés dans le dépôt |

Règles de nommage : `<PROJECT_NAME>` doit être un nom Kubernetes valide (lettres minuscules, chiffres, `-`). Gardez-le identique dans le répertoire de code, le répertoire des manifestes, le namespace et le nom d'hôte.

Suite : [Différences entre local et cloud](local-vs-cloud-differences.md)
