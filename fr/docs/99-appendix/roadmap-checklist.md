# Checklist de la feuille de route

Toutes les étapes dans l'ordre. Une étape est terminée lorsque sa vérification réussit. Les étapes marquées facultatives peuvent être ignorées ou réalisées dans n'importe quel ordre après l'étape 7.

- [ ] **1. OS installé.** Ubuntu Server LTS démarre, le système est à jour, la langue et le fuseau horaire sont définis. Vérification : `lsb_release -a` ; `timedatectl`. Voir [Installer Ubuntu Server](../01-os-and-network/install-ubuntu-server.md).
- [ ] **2. Adresse stable.** Le serveur conserve la même IP après un redémarrage. Vérification : `ip -4 addr` avant et après `sudo reboot`. Voir [IP statique et réseau](../01-os-and-network/static-ip-and-networking.md).
- [ ] **3. SSH renforcé.** Utilisateur sudo non root, connexion par clé fonctionnelle, connexion par mot de passe refusée, port personnalisé. Vérification : `ssh -p <SSH_PORT> <SERVER_USER>@<SERVER_IP>` fonctionne ; `sudo sshd -T | grep -i passwordauthentication` affiche `no`. Voir [Renforcement de SSH](../02-security/ssh-hardening.md).
- [ ] **4. Pare-feu.** Seuls les ports SSH et web sont ouverts. Vérification : `sudo ufw status verbose`. Voir [UFW](../02-security/firewall-ufw.md).
- [ ] **5. Fail2ban.** Jail actif. Vérification : `sudo fail2ban-client status sshd`. Voir [Fail2ban](../02-security/fail2ban.md).
- [ ] **6. Docker.** Vérification : `docker run --rm hello-world`. Voir [Installation de Docker](../03-containers-and-k3s/docker-install.md).
- [ ] **7. K3s.** Nœud Ready, `kubectl` fonctionne depuis le portable. Vérification : `kubectl get nodes`. Voir [Installation de K3s](../03-containers-and-k3s/k3s-install.md).
- [ ] **8. Ingress et première application.** L'application de test s'ouvre par son nom d'hôte dans le navigateur. Vérification : `curl -I http://<PROJECT_NAME>.<DOMAIN_BASE>`. Voir [Ingress et première application](../03-containers-and-k3s/ingress-traefik-first-app.md).
- [ ] **9. Productivité du shell (facultatif).** Le prompt et les alias se chargent. Voir [Starship](../03-containers-and-k3s/shell-productivity-starship.md), [Alias K3s](../03-containers-and-k3s/k3s-productivity-aliases.md).
- [ ] **10. Clés Git.** Vérification : `ssh -T git@github.com` (ou votre hébergeur) vous accueille. Voir [Clés SSH pour Git](../04-git-and-ide/ssh-keys-for-git.md).
- [ ] **11. Identités multiples (facultatif).** Vérification : `git config user.email` dans chaque dossier d'espace de travail renvoie la bonne adresse. Voir [Identités Git multiples](../04-git-and-ide/multiple-git-identities.md).
- [ ] **12. IDE via SSH.** Le projet distant s'ouvre et enregistre les fichiers sur le serveur. Voir [IDE Remote-SSH](../04-git-and-ide/ide-remote-ssh.md).
- [ ] **13. Organisation des manifests.** Code et manifests dans des arborescences séparées. Voir [Structure et conventions](../05-deploying-projects/k8s-structure-conventions.md).
- [ ] **14. Premier vrai projet déployé.** Tous les Pods en `Running`, site accessible. Vérification : `kubectl get pods -n <PROJECT_NAME>`. Voir [Guide de déploiement générique](../05-deploying-projects/generic-deployment-walkthrough.md), [référence des manifests](../05-deploying-projects/manifests-reference/deployment-manifest.md).
- [ ] **15. Médias et base de données migrés.** Les données correspondent à la source. Voir [Migration des médias et de la base de données](../05-deploying-projects/media-and-database-migration.md).
- [ ] **16. Autres projets.** Chacun dans son propre namespace, nom d'hôte et dossier. Voir [Checklist multi-projets](../05-deploying-projects/multi-project-checklist.md).
- [ ] **17. Accès distant (facultatif).** Le tunnel inverse survit au redémarrage ; la connexion via ProxyJump fonctionne. Vérification : `ssh <SERVER_HOSTNAME>` depuis l'extérieur du LAN. Voir [Passerelle VPS](../06-remote-access/vps-gateway-setup.md), [tunnel inverse](../06-remote-access/reverse-ssh-tunnel-systemd.md), [ProxyJump](../06-remote-access/proxyjump-client-config.md).
- [ ] **18. CI/CD (facultatif).** Le pipeline construit et déploie un projet perso à chaque push. Voir [Pipeline GitLab CI](../07-cicd/gitlab-ci-petproject-pipeline.md).
- [ ] **19. Supervision (facultatif).** Grafana affiche les métriques et les logs des nœuds et des Pods. Vérification : `helm list -A`. Voir [Bases de Helm](../08-monitoring/helm-basics.md), [Prometheus et Grafana](../08-monitoring/prometheus-grafana.md), [Loki](../08-monitoring/loki-logs.md).
- [ ] **20. Stockage de fichiers (facultatif).** Partager des montages depuis une autre machine avec un utilisateur restreint. Voir [Samba](../09-optional-extras/samba-file-storage.md).

Concepts : [Glossaire](glossary.md). Problèmes réseau sur matériel local : [Dépannage](troubleshooting-networking.md).

Suivant : [Dépannage réseau](troubleshooting-networking.md)
