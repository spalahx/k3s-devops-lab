# Roadmap checklist

Every stage in order. A stage is done when its check passes. Stages marked optional can be skipped or done in any order after stage 7.

- [ ] **1. OS installed.** Ubuntu Server LTS boots, system updated, locale and timezone set. Check: `lsb_release -a`; `timedatectl`. See [Install Ubuntu Server](../01-os-and-network/install-ubuntu-server.md).
- [ ] **2. Stable address.** Server keeps the same IP after reboot. Check: `ip -4 addr` before and after `sudo reboot`. See [Static IP and networking](../01-os-and-network/static-ip-and-networking.md).
- [ ] **3. SSH hardened.** Non-root sudo user, key login works, password login rejected, custom port. Check: `ssh -p <SSH_PORT> <SERVER_USER>@<SERVER_IP>` works; `sudo sshd -T | grep -i passwordauthentication` shows `no`. See [SSH hardening](../02-security/ssh-hardening.md).
- [ ] **4. Firewall.** Only SSH and web ports open. Check: `sudo ufw status verbose`. See [UFW](../02-security/firewall-ufw.md).
- [ ] **5. Fail2ban.** Jail active. Check: `sudo fail2ban-client status sshd`. See [Fail2ban](../02-security/fail2ban.md).
- [ ] **6. Docker.** Check: `docker run --rm hello-world`. See [Docker install](../03-containers-and-k3s/docker-install.md).
- [ ] **7. K3s.** Node Ready, `kubectl` works from the laptop. Check: `kubectl get nodes`. See [K3s install](../03-containers-and-k3s/k3s-install.md).
- [ ] **8. Ingress and first app.** Test app opens by hostname in the browser. Check: `curl -I http://<PROJECT_NAME>.<DOMAIN_BASE>`. See [Ingress and first app](../03-containers-and-k3s/ingress-traefik-first-app.md).
- [ ] **9. Shell productivity (optional).** Prompt and aliases load. See [Starship](../03-containers-and-k3s/shell-productivity-starship.md), [K3s aliases](../03-containers-and-k3s/k3s-productivity-aliases.md).
- [ ] **10. Git keys.** Check: `ssh -T git@github.com` (or your host) greets you. See [SSH keys for Git](../04-git-and-ide/ssh-keys-for-git.md).
- [ ] **11. Multiple identities (optional).** Check: `git config user.email` inside each workspace folder returns the right address. See [Multiple Git identities](../04-git-and-ide/multiple-git-identities.md).
- [ ] **12. IDE over SSH.** Remote project opens and saves files on the server. See [IDE Remote-SSH](../04-git-and-ide/ide-remote-ssh.md).
- [ ] **13. Manifest layout.** Code and manifests in separate trees. See [Structure and conventions](../05-deploying-projects/k8s-structure-conventions.md).
- [ ] **14. First real project deployed.** All Pods `Running`, site reachable. Check: `kubectl get pods -n <PROJECT_NAME>`. See [Generic deployment walkthrough](../05-deploying-projects/generic-deployment-walkthrough.md), [manifests reference](../05-deploying-projects/manifests-reference/deployment-manifest.md).
- [ ] **15. Media and database migrated.** Data matches the source. See [Media and database migration](../05-deploying-projects/media-and-database-migration.md).
- [ ] **16. More projects.** Each in its own namespace, hostname and folder. See [Multi-project checklist](../05-deploying-projects/multi-project-checklist.md).
- [ ] **17. Remote access (optional).** Reverse tunnel survives reboot; login via ProxyJump works. Check: `ssh <SERVER_HOSTNAME>` from outside the LAN. See [VPS gateway](../06-remote-access/vps-gateway-setup.md), [reverse tunnel](../06-remote-access/reverse-ssh-tunnel-systemd.md), [ProxyJump](../06-remote-access/proxyjump-client-config.md).
- [ ] **18. CI/CD (optional).** Pipeline builds and deploys a pet project on push. See [GitLab CI pipeline](../07-cicd/gitlab-ci-petproject-pipeline.md).
- [ ] **19. Monitoring (optional).** Grafana shows node and Pod metrics and logs. Check: `helm list -A`. See [Helm basics](../08-monitoring/helm-basics.md), [Prometheus and Grafana](../08-monitoring/prometheus-grafana.md), [Loki](../08-monitoring/loki-logs.md).
- [ ] **20. File storage (optional).** Share mounts from another machine with a restricted user. See [Samba](../09-optional-extras/samba-file-storage.md).

Concepts: [Glossary](glossary.md). Network problems on local hardware: [Troubleshooting](troubleshooting-networking.md).

Next: [Troubleshooting networking](troubleshooting-networking.md)
