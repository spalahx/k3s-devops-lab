# Документація

Читати по порядку. Наприкінці кожної сторінки є посилання на наступну. Плейсхолдери на кшталт `<SERVER_USER>` перелічено в розділі [Вимоги та змінні](docs/00-overview/prerequisites-and-variables.md).

## Огляд

- [Вступ](docs/00-overview/introduction.md)
- [Огляд архітектури](docs/00-overview/architecture-overview.md)
- [Вимоги та змінні](docs/00-overview/prerequisites-and-variables.md)
- [Відмінності локального та хмарного середовища](docs/00-overview/local-vs-cloud-differences.md)

## ОС і мережа

- [Встановлення Ubuntu Server](docs/01-os-and-network/install-ubuntu-server.md)
- [Статична IP-адреса та мережа](docs/01-os-and-network/static-ip-and-networking.md)

## Безпека

- [Захист SSH](docs/02-security/ssh-hardening.md)
- [Брандмауер (UFW)](docs/02-security/firewall-ufw.md)
- [Fail2ban](docs/02-security/fail2ban.md)

## Контейнери та K3s

- [Встановлення Docker Engine](docs/03-containers-and-k3s/docker-install.md)
- [Встановлення K3s](docs/03-containers-and-k3s/k3s-install.md)
- [Ingress з Traefik і перший застосунок](docs/03-containers-and-k3s/ingress-traefik-first-app.md)
- [Продуктивність оболонки: Starship і ble.sh](docs/03-containers-and-k3s/shell-productivity-starship.md)
- [Аліаси kubectl і помічники для проєктів](docs/03-containers-and-k3s/k3s-productivity-aliases.md)

## Git та IDE

- [SSH-ключі для Git](docs/04-git-and-ide/ssh-keys-for-git.md)
- [Кілька ідентичностей Git](docs/04-git-and-ide/multiple-git-identities.md)
- [IDE через SSH і код у подах](docs/04-git-and-ide/ide-remote-ssh.md)

## Деплой проєктів

- [Угоди про каталоги та іменування: код і маніфести](docs/05-deploying-projects/k8s-structure-conventions.md)
- [Розгортання проєкту від початку до кінця](docs/05-deploying-projects/generic-deployment-walkthrough.md)
- [Довідник: маніфест застосунку (`app.yaml`)](docs/05-deploying-projects/manifests-reference/deployment-manifest.md)
- [Довідник: маніфест бази даних (`db.yaml`)](docs/05-deploying-projects/manifests-reference/database-manifest.md)
- [Довідник: маніфест phpMyAdmin (`phpmyadmin.yaml`)](docs/05-deploying-projects/manifests-reference/phpmyadmin-manifest.md)
- [Міграція наявного сайту WordPress: медіафайли та база даних](docs/05-deploying-projects/media-and-database-migration.md)
- [Кілька проєктів одночасно](docs/05-deploying-projects/multi-project-checklist.md)

## Віддалений доступ

- [Налаштування VPS-шлюзу](docs/06-remote-access/vps-gateway-setup.md)
- [Зворотний SSH-тунель як служба systemd](docs/06-remote-access/reverse-ssh-tunnel-systemd.md)
- [Клієнтська конфігурація ProxyJump](docs/06-remote-access/proxyjump-client-config.md)

## CI/CD

- [Конвеєр GitLab CI: збірка та розгортання в K3s](docs/07-cicd/gitlab-ci-petproject-pipeline.md)

## Моніторинг

- [Основи Helm](docs/08-monitoring/helm-basics.md)
- [Prometheus і Grafana](docs/08-monitoring/prometheus-grafana.md)
- [Журнали Loki](docs/08-monitoring/loki-logs.md)

## Додатково

- [Файлове сховище Samba](docs/09-optional-extras/samba-file-storage.md)
- [Ollama в окремому namespace](docs/09-optional-extras/ollama-ai-namespace.md)

## Додатки

- [Чек-лист дорожньої карти](docs/99-appendix/roadmap-checklist.md)
- [Усунення мережевих проблем (лише локальне обладнання)](docs/99-appendix/troubleshooting-networking.md)
- [Глосарій](docs/99-appendix/glossary.md)

Готові маніфести: [examples/wordpress](examples/wordpress/).

[На головну](../README.uk.md)
