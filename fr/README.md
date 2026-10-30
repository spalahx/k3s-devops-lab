# Documentation

À lire dans l'ordre. Chaque page se termine par un lien vers la suivante. Les espaces réservés comme `<SERVER_USER>` sont listés dans [Prérequis et variables](docs/00-overview/prerequisites-and-variables.md).

## Vue d'ensemble

- [Vue d'ensemble de l'architecture](docs/00-overview/architecture-overview.md)
- [Introduction](docs/00-overview/introduction.md)
- [Différences entre local et cloud](docs/00-overview/local-vs-cloud-differences.md)
- [Prérequis et variables](docs/00-overview/prerequisites-and-variables.md)

## Système et réseau

- [Installer Ubuntu Server](docs/01-os-and-network/install-ubuntu-server.md)
- [IP statique et réseau](docs/01-os-and-network/static-ip-and-networking.md)

## Sécurité

- [Fail2ban](docs/02-security/fail2ban.md)
- [Pare-feu (UFW)](docs/02-security/firewall-ufw.md)
- [Renforcement de SSH](docs/02-security/ssh-hardening.md)

## Conteneurs et K3s

- [Installation de Docker Engine](docs/03-containers-and-k3s/docker-install.md)
- [Ingress avec Traefik et une première application](docs/03-containers-and-k3s/ingress-traefik-first-app.md)
- [Installation de K3s](docs/03-containers-and-k3s/k3s-install.md)
- [Alias kubectl et utilitaires de projet](docs/03-containers-and-k3s/k3s-productivity-aliases.md)
- [Productivité du shell : Starship et ble.sh](docs/03-containers-and-k3s/shell-productivity-starship.md)

## Git et IDE

- [IDE via SSH et code dans les Pods](docs/04-git-and-ide/ide-remote-ssh.md)
- [Identités Git multiples](docs/04-git-and-ide/multiple-git-identities.md)
- [Clés SSH pour Git](docs/04-git-and-ide/ssh-keys-for-git.md)

## Déploiement des projets

- [Déployer un projet de bout en bout](docs/05-deploying-projects/generic-deployment-walkthrough.md)
- [Conventions de répertoires et de nommage : code et manifestes](docs/05-deploying-projects/k8s-structure-conventions.md)
- [Référence : manifeste de la base de données (`db.yaml`)](docs/05-deploying-projects/manifests-reference/database-manifest.md)
- [Référence : manifeste de l'application (`app.yaml`)](docs/05-deploying-projects/manifests-reference/deployment-manifest.md)
- [Référence : manifeste phpMyAdmin (`phpmyadmin.yaml`)](docs/05-deploying-projects/manifests-reference/phpmyadmin-manifest.md)
- [Migrer un site WordPress existant : médias et base de données](docs/05-deploying-projects/media-and-database-migration.md)
- [Faire tourner plusieurs projets côte à côte](docs/05-deploying-projects/multi-project-checklist.md)

## Accès distant

- [Configuration client ProxyJump](docs/06-remote-access/proxyjump-client-config.md)
- [Tunnel SSH inverse en tant que service systemd](docs/06-remote-access/reverse-ssh-tunnel-systemd.md)
- [Configuration de la passerelle VPS](docs/06-remote-access/vps-gateway-setup.md)

## CI/CD

- [Pipeline GitLab CI : build et déploiement sur K3s](docs/07-cicd/gitlab-ci-petproject-pipeline.md)

## Supervision

- [Bases de Helm](docs/08-monitoring/helm-basics.md)
- [Journaux Loki](docs/08-monitoring/loki-logs.md)
- [Prometheus et Grafana](docs/08-monitoring/prometheus-grafana.md)

## Extras facultatifs

- [Ollama dans un namespace dédié](docs/09-optional-extras/ollama-ai-namespace.md)
- [Stockage de fichiers Samba](docs/09-optional-extras/samba-file-storage.md)

## Annexes

- [Glossaire](docs/99-appendix/glossary.md)
- [Checklist de la feuille de route](docs/99-appendix/roadmap-checklist.md)
- [Dépannage réseau (matériel local uniquement)](docs/99-appendix/troubleshooting-networking.md)

Manifestes prêts à l'emploi : [examples/wordpress](examples/wordpress/).

[Retour à la page principale](../README.fr.md)
