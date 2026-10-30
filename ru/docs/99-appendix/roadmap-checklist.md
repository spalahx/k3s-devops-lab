# Чек-лист этапов

Все этапы по порядку. Этап выполнен, когда проходит его проверка. Опциональные этапы можно пропускать или делать в любом порядке после этапа 7.

- [ ] **1. ОС установлена.** Ubuntu Server LTS загружается, система обновлена, локаль и часовой пояс заданы. Проверка: `lsb_release -a`; `timedatectl`. См. [Установка Ubuntu Server](../01-os-and-network/install-ubuntu-server.md).
- [ ] **2. Стабильный адрес.** После перезагрузки IP сервера не меняется. Проверка: `ip -4 addr` до и после `sudo reboot`. См. [Статический IP и сеть](../01-os-and-network/static-ip-and-networking.md).
- [ ] **3. SSH защищён.** Обычный пользователь с sudo, вход по ключу работает, вход по паролю отклоняется, порт нестандартный. Проверка: работает `ssh -p <SSH_PORT> <SERVER_USER>@<SERVER_IP>`; `sudo sshd -T | grep -i passwordauthentication` показывает `no`. См. [Харденинг SSH](../02-security/ssh-hardening.md).
- [ ] **4. Firewall.** Открыты только SSH и веб-порты. Проверка: `sudo ufw status verbose`. См. [UFW](../02-security/firewall-ufw.md).
- [ ] **5. Fail2ban.** Jail активен. Проверка: `sudo fail2ban-client status sshd`. См. [Fail2ban](../02-security/fail2ban.md).
- [ ] **6. Docker.** Проверка: `docker run --rm hello-world`. См. [Установка Docker](../03-containers-and-k3s/docker-install.md).
- [ ] **7. K3s.** Узел Ready, `kubectl` работает с ноутбука. Проверка: `kubectl get nodes`. См. [Установка K3s](../03-containers-and-k3s/k3s-install.md).
- [ ] **8. Ingress и первое приложение.** Тестовое приложение открывается в браузере по имени хоста. Проверка: `curl -I http://<PROJECT_NAME>.<DOMAIN_BASE>`. См. [Ingress и первое приложение](../03-containers-and-k3s/ingress-traefik-first-app.md).
- [ ] **9. Удобство работы в shell (опционально).** Приглашение и алиасы загружаются. См. [Starship](../03-containers-and-k3s/shell-productivity-starship.md), [алиасы K3s](../03-containers-and-k3s/k3s-productivity-aliases.md).
- [ ] **10. Ключи для Git.** Проверка: `ssh -T git@github.com` (или ваш хостинг) приветствует вас. См. [SSH-ключи для Git](../04-git-and-ide/ssh-keys-for-git.md).
- [ ] **11. Несколько Git-личностей (опционально).** Проверка: `git config user.email` в каждой папке workspace возвращает правильный адрес. См. [Несколько Git-личностей](../04-git-and-ide/multiple-git-identities.md).
- [ ] **12. IDE по SSH.** Удалённый проект открывается и сохраняет файлы на сервере. См. [IDE Remote-SSH](../04-git-and-ide/ide-remote-ssh.md).
- [ ] **13. Структура манифестов.** Код и манифесты лежат в разных деревьях. См. [Структура и соглашения](../05-deploying-projects/k8s-structure-conventions.md).
- [ ] **14. Первый реальный проект развёрнут.** Все Pod в состоянии `Running`, сайт доступен. Проверка: `kubectl get pods -n <PROJECT_NAME>`. См. [Универсальный пример деплоя](../05-deploying-projects/generic-deployment-walkthrough.md), [справочник манифестов](../05-deploying-projects/manifests-reference/deployment-manifest.md).
- [ ] **15. Медиа и БД перенесены.** Данные совпадают с источником. См. [Миграция медиа и БД](../05-deploying-projects/media-and-database-migration.md).
- [ ] **16. Дополнительные проекты.** Каждый в своём namespace, с отдельным именем хоста и папкой. См. [Чек-лист нескольких проектов](../05-deploying-projects/multi-project-checklist.md).
- [ ] **17. Удалённый доступ (опционально).** Обратный туннель переживает перезагрузку; вход через ProxyJump работает. Проверка: `ssh <SERVER_HOSTNAME>` снаружи LAN. См. [VPS-шлюз](../06-remote-access/vps-gateway-setup.md), [обратный туннель](../06-remote-access/reverse-ssh-tunnel-systemd.md), [ProxyJump](../06-remote-access/proxyjump-client-config.md).
- [ ] **18. CI/CD (опционально).** Пайплайн собирает и деплоит пет-проект при push. См. [Пайплайн GitLab CI](../07-cicd/gitlab-ci-petproject-pipeline.md).
- [ ] **19. Мониторинг (опционально).** Grafana показывает метрики узла и Pod, а также логи. Проверка: `helm list -A`. См. [Основы Helm](../08-monitoring/helm-basics.md), [Prometheus и Grafana](../08-monitoring/prometheus-grafana.md), [Loki](../08-monitoring/loki-logs.md).
- [ ] **20. Файловое хранилище (опционально).** Шара монтируется с другой машины под ограниченным пользователем. См. [Samba](../09-optional-extras/samba-file-storage.md).
- [ ] **21. Локальные LLM (опционально).** Ollama отвечает внутри кластера, лимиты ресурсов заданы. См. [Ollama](../09-optional-extras/ollama-ai-namespace.md).

Термины: [Глоссарий](glossary.md). Проблемы сети на локальном железе: [Диагностика](troubleshooting-networking.md).

Далее: [Диагностика сети](troubleshooting-networking.md)
