# Glossaire

| Terme | Signification |
|---|---|
| ClusterIP | Type de Service par défaut : une IP virtuelle accessible uniquement à l'intérieur du cluster |
| ConfigMap | Objet Kubernetes contenant une configuration non secrète, monté sous forme de fichiers ou de variables d'environnement |
| Container | Processus isolé, empaqueté avec ses dépendances, démarré à partir d'une image |
| containerd | Runtime de conteneurs utilisé par K3s pour exécuter les Pods |
| CNI | Container Network Interface : plugin qui donne l'accès réseau aux Pods (Flannel dans K3s) |
| Deployment | Objet qui maintient en fonctionnement un nombre voulu de Pods identiques et gère les mises à jour |
| DHCP reservation | Réglage du routeur qui attribue toujours la même IP LAN à une adresse MAC donnée |
| Docker | Outil pour construire des images et exécuter des conteneurs |
| ed25519 | Type de clé SSH moderne ; courte et robuste |
| Fail2ban | Service qui bannit des IP après des échecs de connexion répétés en lisant les logs |
| Flannel | Plugin CNI par défaut de K3s fournissant le réseau des Pods |
| Grafana | Interface web de tableaux de bord construits à partir des données de Prometheus et Loki |
| Helm | Gestionnaire de paquets pour Kubernetes ; installe les applications sous forme de charts versionnés |
| Helm chart | Ensemble empaqueté de manifests Kubernetes avec des valeurs configurables |
| hostPath | Type de volume qui monte un répertoire du nœud dans un Pod |
| HWE | Hardware Enablement : pile de noyau plus récente pour une version Ubuntu LTS |
| Image | Modèle en lecture seule à partir duquel un conteneur est démarré |
| Ingress | Objet définissant les règles de routage HTTP des noms d'hôte/chemins vers les Services |
| includeIf | Directive de configuration Git qui charge des paramètres supplémentaires selon le chemin du dépôt |
| K3s | Distribution Kubernetes légère, un seul binaire, inclut Traefik |
| kubeconfig | Fichier contenant l'adresse du cluster et les identifiants utilisés par `kubectl` (`~/.kube/config`) |
| kubectl | Client en ligne de commande de l'API Kubernetes |
| Kubernetes (K8s) | Système qui planifie et supervise des conteneurs sur plusieurs machines |
| Loki | Système de stockage de logs de Grafana Labs, indexé par labels |
| LTS | Version à support à long terme (Ubuntu LTS reçoit des mises à jour de sécurité pendant cinq ans) |
| Manifest | Fichier YAML décrivant des objets Kubernetes |
| Namespace | Partition logique d'un cluster ; les noms et quotas sont délimités par namespace |
| netplan | Outil de configuration réseau d'Ubuntu piloté par du YAML dans `/etc/netplan/` |
| Node | Une machine du cluster ; ici, le serveur unique |
| Ollama | Outil qui exécute des grands modèles de langage en local |
| Pod | Plus petite unité déployable : un ou plusieurs conteneurs partageant réseau et volumes |
| Prometheus | Base de données de séries temporelles qui collecte et stocke les métriques |
| Promtail | Agent qui envoie les logs des conteneurs et du système vers Loki |
| ProxyJump | Option SSH (`-J`) pour se connecter à une cible via un hôte intermédiaire |
| PV / PVC | PersistentVolume et PersistentVolumeClaim : le stockage et la demande de stockage d'un Pod |
| Remote-SSH | Fonction d'IDE qui ouvre et modifie un dossier d'une machine distante via SSH |
| Reverse SSH tunnel | Connexion ouverte depuis le serveur vers un VPS qui expose un port du serveur sur le VPS |
| rfkill | Utilitaire qui affiche et active/désactive les blocages radio matériels et logiciels |
| Samba (SMB) | Protocole et serveur de partages de fichiers réseau utilisables depuis macOS et Linux |
| Secret | Objet Kubernetes pour les valeurs sensibles comme les mots de passe |
| Service | Adresse interne stable et répartiteur de charge devant un ensemble de Pods |
| SFTP | Transfert de fichiers via SSH |
| sshd_config | Fichier de configuration du serveur OpenSSH (`/etc/ssh/sshd_config`) |
| Starship | Prompt multi-shell qui affiche le contexte git, Kubernetes et autres |
| systemd | Système d'init et gestionnaire de services ; exécute des unités comme le service de tunnel |
| Traefik | Contrôleur Ingress/reverse proxy inclus dans K3s |
| UFW | Uncomplicated Firewall : interface pour iptables/nftables |
| VPS | Serveur privé virtuel loué auprès d'un fournisseur cloud, généralement avec une IP publique fixe |
| YAML | Format de données basé sur l'indentation utilisé pour les manifests et netplan |

Suivant : [Introduction](../00-overview/introduction.md)
