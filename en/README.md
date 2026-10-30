# Documentation

Read in order. Each page ends with a link to the next one. Placeholders like `<SERVER_USER>` are listed in [Prerequisites and variables](docs/00-overview/prerequisites-and-variables.md).

## Overview

- [Introduction](docs/00-overview/introduction.md)
- [Architecture overview](docs/00-overview/architecture-overview.md)
- [Prerequisites and variables](docs/00-overview/prerequisites-and-variables.md)
- [Local vs cloud differences](docs/00-overview/local-vs-cloud-differences.md)

## OS and network

- [Install Ubuntu Server](docs/01-os-and-network/install-ubuntu-server.md)
- [Static IP and Networking](docs/01-os-and-network/static-ip-and-networking.md)

## Security

- [SSH Hardening](docs/02-security/ssh-hardening.md)
- [Firewall (UFW)](docs/02-security/firewall-ufw.md)
- [Fail2ban](docs/02-security/fail2ban.md)

## Containers and K3s

- [Docker Engine Install](docs/03-containers-and-k3s/docker-install.md)
- [K3s Install](docs/03-containers-and-k3s/k3s-install.md)
- [Ingress with Traefik and a First App](docs/03-containers-and-k3s/ingress-traefik-first-app.md)
- [Shell Productivity: Starship and ble.sh](docs/03-containers-and-k3s/shell-productivity-starship.md)
- [kubectl Aliases and Project Helpers](docs/03-containers-and-k3s/k3s-productivity-aliases.md)

## Git and IDE

- [SSH Keys for Git](docs/04-git-and-ide/ssh-keys-for-git.md)
- [Multiple Git Identities](docs/04-git-and-ide/multiple-git-identities.md)
- [IDE over SSH and Code in Pods](docs/04-git-and-ide/ide-remote-ssh.md)

## Deploying projects

- [Directory and Naming Conventions: Code vs Manifests](docs/05-deploying-projects/k8s-structure-conventions.md)
- [Deploying a Project End to End](docs/05-deploying-projects/generic-deployment-walkthrough.md)
- [Reference: Application Manifest (`app.yaml`)](docs/05-deploying-projects/manifests-reference/deployment-manifest.md)
- [Reference: Database Manifest (`db.yaml`)](docs/05-deploying-projects/manifests-reference/database-manifest.md)
- [Reference: phpMyAdmin Manifest (`phpmyadmin.yaml`)](docs/05-deploying-projects/manifests-reference/phpmyadmin-manifest.md)
- [Migrating an Existing WordPress Site: Media and Database](docs/05-deploying-projects/media-and-database-migration.md)
- [Running Several Projects Side by Side](docs/05-deploying-projects/multi-project-checklist.md)

## Remote access

- [VPS Gateway Setup](docs/06-remote-access/vps-gateway-setup.md)
- [Reverse SSH Tunnel as a systemd Service](docs/06-remote-access/reverse-ssh-tunnel-systemd.md)
- [ProxyJump Client Config](docs/06-remote-access/proxyjump-client-config.md)

## CI/CD

- [GitLab CI Pipeline: Build and Deploy to K3s](docs/07-cicd/gitlab-ci-petproject-pipeline.md)

## Monitoring

- [Helm Basics](docs/08-monitoring/helm-basics.md)
- [Prometheus and Grafana](docs/08-monitoring/prometheus-grafana.md)
- [Loki Logs](docs/08-monitoring/loki-logs.md)

## Optional extras

- [Samba File Storage](docs/09-optional-extras/samba-file-storage.md)
- [Ollama in a Separate Namespace](docs/09-optional-extras/ollama-ai-namespace.md)

## Appendix

- [Roadmap checklist](docs/99-appendix/roadmap-checklist.md)
- [Troubleshooting networking (local hardware only)](docs/99-appendix/troubleshooting-networking.md)
- [Glossary](docs/99-appendix/glossary.md)

Ready-to-use manifests: [examples/wordpress](examples/wordpress/).

[Back to the main page](../README.md)
