# Introduction

Une seule machine Ubuntu Server (un mini-PC à domicile ou un VPS dans le cloud) exécute K3s, une version légère de Kubernetes. Chaque projet est décrit par des manifestes YAML, et la machine est administrée en SSH depuis un portable. Passez cette installation si un simple fichier `docker compose` sur le portable répond déjà à vos besoins.

## Ce que vous obtenez

- Un hôte Linux toujours allumé avec un point d'entrée SSH renforcé (connexion par clé uniquement, pare-feu, protection contre la force brute).
- Docker pour construire les images et K3s pour les exécuter ; Traefik route le trafic HTTP vers les projets selon le nom d'hôte.
- Du code sur le serveur, édité depuis l'IDE du portable via Remote-SSH ; les modifications apparaissent dans les Pods en cours d'exécution grâce aux volumes `hostPath`.
- Optionnel : accès distant via un VPS, CI/CD, supervision (Prometheus, Grafana, Loki), stockage de fichiers.

## Quand c'est utile

- **Portable faible ou chargé.** Les bases de données, plusieurs piles web et un navigateur ne cohabitent pas bien ; déplacez l'exécution sur le serveur et ne gardez que l'IDE en local.
- **Serveur de développement partagé pour une petite équipe.** Un hôte, un namespace par projet, chacun se connecte en SSH avec sa propre clé.
- **Travail parallèle sur plusieurs projets et tests d'intégration.** Plusieurs projets tournent côte à côte sur des noms d'hôte différents, sans conflit de ports ni de dépendances.
- **Environnement proche de la production.** Les mêmes objets Kubernetes (Deployment, Service, Ingress) que ceux utilisés en production sont exercés pendant le développement.
- **Expérimentations.** Namespaces jetables et nouveaux outils avec des limites de ressources pour ne pas priver les autres projets.

## Ordre de lecture

1. Vue d'ensemble : [Architecture](architecture-overview.md), [Prérequis et variables](prerequisites-and-variables.md), [Local vs cloud](local-vs-cloud-differences.md).
2. Système de base : [OS et réseau](../01-os-and-network/install-ubuntu-server.md), puis [Sécurité](../02-security/ssh-hardening.md). Faites les deux avant d'installer quoi que ce soit d'autre.
3. Plateforme : [Docker](../03-containers-and-k3s/docker-install.md), [K3s](../03-containers-and-k3s/k3s-install.md), [Ingress et première application](../03-containers-and-k3s/ingress-traefik-first-app.md).
4. Flux de travail : [Git et IDE](../04-git-and-ide/ssh-keys-for-git.md), puis [Déploiement des projets](../05-deploying-projects/k8s-structure-conventions.md).
5. Optionnel, dans n'importe quel ordre : [Accès distant](../06-remote-access/vps-gateway-setup.md), [CI/CD](../07-cicd/gitlab-ci-petproject-pipeline.md), [Supervision](../08-monitoring/helm-basics.md), [Extras](../09-optional-extras/samba-file-storage.md).

La liste de contrôle complète et ordonnée se trouve dans la [Liste de contrôle de la feuille de route](../99-appendix/roadmap-checklist.md).

Suite : [Vue d'ensemble de l'architecture](architecture-overview.md)
