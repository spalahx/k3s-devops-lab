# Чек-лист дорожньої карти

Усі етапи по порядку. Етап вважається виконаним, коли його перевірка проходить. Етапи з позначкою «необов'язково» можна пропустити або виконати в будь-якому порядку після етапу 7.

- [ ] **1. ОС встановлено.** Ubuntu Server LTS завантажується, систему оновлено, локаль і часовий пояс задано. Перевірка: `lsb_release -a`; `timedatectl`. Див. [Встановлення Ubuntu Server](../01-os-and-network/install-ubuntu-server.md).
- [ ] **2. Стабільна адреса.** Сервер зберігає ту саму IP-адресу після перезавантаження. Перевірка: `ip -4 addr` до і після `sudo reboot`. Див. [Статична IP-адреса та мережа](../01-os-and-network/static-ip-and-networking.md).
- [ ] **3. SSH захищено.** Користувач із sudo без root, вхід за ключем працює, вхід за паролем відхиляється, нестандартний порт. Перевірка: `ssh -p <SSH_PORT> <SERVER_USER>@<SERVER_IP>` працює; `sudo sshd -T | grep -i passwordauthentication` показує `no`. Див. [Захист SSH](../02-security/ssh-hardening.md).
- [ ] **4. Брандмауер.** Відкриті лише порти SSH і вебу. Перевірка: `sudo ufw status verbose`. Див. [UFW](../02-security/firewall-ufw.md).
- [ ] **5. Fail2ban.** Jail активний. Перевірка: `sudo fail2ban-client status sshd`. Див. [Fail2ban](../02-security/fail2ban.md).
- [ ] **6. Docker.** Перевірка: `docker run --rm hello-world`. Див. [Встановлення Docker](../03-containers-and-k3s/docker-install.md).
- [ ] **7. K3s.** Вузол у стані Ready, `kubectl` працює з ноутбука. Перевірка: `kubectl get nodes`. Див. [Встановлення K3s](../03-containers-and-k3s/k3s-install.md).
- [ ] **8. Ingress і перший застосунок.** Тестовий застосунок відкривається в браузері за іменем хоста. Перевірка: `curl -I http://<PROJECT_NAME>.<DOMAIN_BASE>`. Див. [Ingress і перший застосунок](../03-containers-and-k3s/ingress-traefik-first-app.md).
- [ ] **9. Продуктивність оболонки (необов'язково).** Підказка командного рядка та аліаси завантажуються. Див. [Starship](../03-containers-and-k3s/shell-productivity-starship.md), [Аліаси K3s](../03-containers-and-k3s/k3s-productivity-aliases.md).
- [ ] **10. Ключі Git.** Перевірка: `ssh -T git@github.com` (або ваш хостинг) вітає вас. Див. [SSH-ключі для Git](../04-git-and-ide/ssh-keys-for-git.md).
- [ ] **11. Кілька профілів (необов'язково).** Перевірка: `git config user.email` у кожній робочій теці повертає правильну адресу. Див. [Кілька профілів Git](../04-git-and-ide/multiple-git-identities.md).
- [ ] **12. IDE через SSH.** Віддалений проєкт відкривається, а файли зберігаються на сервері. Див. [IDE Remote-SSH](../04-git-and-ide/ide-remote-ssh.md).
- [ ] **13. Структура маніфестів.** Код і маніфести в окремих деревах. Див. [Структура та домовленості](../05-deploying-projects/k8s-structure-conventions.md).
- [ ] **14. Перший справжній проєкт розгорнуто.** Усі Pod у стані `Running`, сайт доступний. Перевірка: `kubectl get pods -n <PROJECT_NAME>`. Див. [Загальний покроковий посібник із розгортання](../05-deploying-projects/generic-deployment-walkthrough.md), [довідник маніфестів](../05-deploying-projects/manifests-reference/deployment-manifest.md).
- [ ] **15. Медіа та базу даних перенесено.** Дані збігаються з джерелом. Див. [Міграція медіа та бази даних](../05-deploying-projects/media-and-database-migration.md).
- [ ] **16. Більше проєктів.** Кожен у власному просторі імен, з власним іменем хоста й текою. Див. [Чек-лист для кількох проєктів](../05-deploying-projects/multi-project-checklist.md).
- [ ] **17. Віддалений доступ (необов'язково).** Зворотний тунель переживає перезавантаження; вхід через ProxyJump працює. Перевірка: `ssh <SERVER_HOSTNAME>` ззовні локальної мережі. Див. [VPS-шлюз](../06-remote-access/vps-gateway-setup.md), [зворотний тунель](../06-remote-access/reverse-ssh-tunnel-systemd.md), [ProxyJump](../06-remote-access/proxyjump-client-config.md).
- [ ] **18. CI/CD (необов'язково).** Пайплайн збирає та розгортає навчальний проєкт після push. Див. [Пайплайн GitLab CI](../07-cicd/gitlab-ci-petproject-pipeline.md).
- [ ] **19. Моніторинг (необов'язково).** Grafana показує метрики та логи вузла й Pod. Перевірка: `helm list -A`. Див. [Основи Helm](../08-monitoring/helm-basics.md), [Prometheus і Grafana](../08-monitoring/prometheus-grafana.md), [Loki](../08-monitoring/loki-logs.md).
- [ ] **20. Файлове сховище (необов'язково).** Спільний ресурс з іншої машини монтується через обмеженого користувача. Див. [Samba](../09-optional-extras/samba-file-storage.md).

Поняття: [Глосарій](glossary.md). Мережеві проблеми на локальному обладнанні: [Усунення проблем](troubleshooting-networking.md).

Далі: [Усунення мережевих проблем](troubleshooting-networking.md)
