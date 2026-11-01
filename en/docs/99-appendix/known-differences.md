# Known Differences and Problems Not Covered

How this guide was made: it was written from the author's working notes while setting up a home server, then edited into its current form. It has not been replayed from scratch on a clean machine. This page lists what is known to differ between the text and that reference server (Ubuntu 26.04, K3s v1.36, one node), and problems the author met that the chapters do not describe. A tested, automated track is in development; until it is published, treat the commands here as a well-documented starting point, not as a guarantee.

## Where the reference server differs from the text

| Topic | Text says | Reference server | Which one to follow |
|---|---|---|---|
| SSH password login | `01-hardening.conf` with `PasswordAuthentication no` | `no` is set only in the main `sshd_config`; `50-cloud-init.conf` sets `yes` and wins, so password login is still enabled | The text. Check with `sudo sshd -T` |
| UFW and ports 80/443 | Allow 80/443 (optionally LAN only) | No UFW rule for them, yet Traefik answers from the LAN | UFW does not control these ports; use the router or cloud firewall (see [Firewall](../02-security/firewall-ufw.md)) |
| UFW and K3s networks | Allow `10.42.0.0/16`, `10.43.0.0/16` | No such rules, cluster works | Optional fallback if pods lose DNS |
| Samba | Dedicated `share` folder, LAN only | The whole home directory is shared, UFW rule has no source restriction | The text |
| Fail2ban | Short `jail.local` with overrides only | A full copy of `jail.conf` with the `[sshd]` section edited (port, retries, ban time) | The text |
| Docker | `docker-ce` from Docker's apt repository | `docker.io` from the Ubuntu repository | Either; the text mentions both |
| Host names | `.test` or a domain you own | `.local` names over HTTP, resolved from hosts files | The text; `.local` is reserved for mDNS |
| Static address | DHCP reservation on the router, or netplan | DHCP reservation on the router, netplan stays on DHCP | Both are valid |
| Monitoring | Prometheus, Grafana, Loki, Promtail; control-plane scrapers disabled; 7-day retention | Prometheus stack and Loki are installed; no log shipper; control-plane scrapers not disabled (they stay `down` on K3s); 15-day Prometheus retention; Loki canary enabled | The text for scrapers; for log shipping see the note in [Loki logs](../08-monitoring/loki-logs.md) |

## Not verified on the reference server

- [VPS gateway](../06-remote-access/vps-gateway-setup.md), [reverse tunnel](../06-remote-access/reverse-ssh-tunnel-systemd.md), [ProxyJump](../06-remote-access/proxyjump-client-config.md): no tunnel service or VPS was available for the check.
- [GitLab CI](../07-cicd/gitlab-ci-petproject-pipeline.md): no GitLab Runner installed.
- Promtail steps in [Loki logs](../08-monitoring/loki-logs.md).
- A full end-to-end replay of [Deploying a project](../05-deploying-projects/generic-deployment-walkthrough.md) on a clean machine.

## Problems the chapters do not describe

- **Ownership and permissions change after `git clone` or `git pull` on the server.** Directory owners and modes often differ from what the application container expects, so the application cannot write to its directories. [IDE over SSH](../04-git-and-ide/ide-remote-ssh.md) (section 5) and [Deploying a project](../05-deploying-projects/generic-deployment-walkthrough.md) (step 2) describe `chown`/`chmod`; expect to repeat them after fresh clones.
- **WordPress plugin and theme updates from the admin page can fail.** The most likely cause is the same owner/group mismatch between the user who edits files and the user the web process runs as, so the web process cannot write to `wp-content`. This was not reproduced and fixed in this guide.
- **Remote editing.** PhpStorm and VS Code over SSH are described in [IDE over SSH](../04-git-and-ide/ide-remote-ssh.md). Step-by-step instructions with screenshots and for other editors are planned.

If you hit something that is not listed here, please open an issue with the command, the output and your OS version.
