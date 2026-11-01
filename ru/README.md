# Документация

Читать по порядку. В конце каждой страницы ссылка на следующую. Плейсхолдеры вроде `<SERVER_USER>` перечислены в разделе [Требования и переменные](docs/00-overview/prerequisites-and-variables.md).

## Обзор

- [Введение](docs/00-overview/introduction.md)
- [Обзор архитектуры](docs/00-overview/architecture-overview.md)
- [Требования и переменные](docs/00-overview/prerequisites-and-variables.md)
- [Локальный сервер и облако: различия](docs/00-overview/local-vs-cloud-differences.md)

## ОС и сеть

- [Установка Ubuntu Server](docs/01-os-and-network/install-ubuntu-server.md)
- [Статический IP и сеть](docs/01-os-and-network/static-ip-and-networking.md)

## Безопасность

- [Укрепление SSH](docs/02-security/ssh-hardening.md)
- [Фаервол (UFW)](docs/02-security/firewall-ufw.md)
- [Fail2ban](docs/02-security/fail2ban.md)

## Контейнеры и K3s

- [Установка Docker Engine](docs/03-containers-and-k3s/docker-install.md)
- [Установка K3s](docs/03-containers-and-k3s/k3s-install.md)
- [Ingress через Traefik и первое приложение](docs/03-containers-and-k3s/ingress-traefik-first-app.md)
- [Продуктивность в шелле: Starship и ble.sh](docs/03-containers-and-k3s/shell-productivity-starship.md)
- [Алиасы kubectl и хелперы проектов](docs/03-containers-and-k3s/k3s-productivity-aliases.md)

## Git и IDE

- [SSH-ключи для Git](docs/04-git-and-ide/ssh-keys-for-git.md)
- [Несколько Git-идентичностей](docs/04-git-and-ide/multiple-git-identities.md)
- [IDE по SSH и код в Pod](docs/04-git-and-ide/ide-remote-ssh.md)

## Деплой проектов

- [Структура каталогов и правила именования: код и манифесты](docs/05-deploying-projects/k8s-structure-conventions.md)
- [Развёртывание проекта от начала до конца](docs/05-deploying-projects/generic-deployment-walkthrough.md)
- [Справочник: манифест приложения (`app.yaml`)](docs/05-deploying-projects/manifests-reference/deployment-manifest.md)
- [Справочник: манифест базы данных (`db.yaml`)](docs/05-deploying-projects/manifests-reference/database-manifest.md)
- [Справочник: манифест phpMyAdmin (`phpmyadmin.yaml`)](docs/05-deploying-projects/manifests-reference/phpmyadmin-manifest.md)
- [Перенос существующего WordPress-сайта: медиа и база данных](docs/05-deploying-projects/media-and-database-migration.md)
- [Несколько проектов на одном сервере](docs/05-deploying-projects/multi-project-checklist.md)

## Удалённый доступ

- [Настройка VPS-шлюза](docs/06-remote-access/vps-gateway-setup.md)
- [Reverse SSH tunnel как служба systemd](docs/06-remote-access/reverse-ssh-tunnel-systemd.md)
- [Клиентская конфигурация ProxyJump](docs/06-remote-access/proxyjump-client-config.md)

## CI/CD

- [GitLab CI pipeline: сборка и деплой в K3s](docs/07-cicd/gitlab-ci-petproject-pipeline.md)

## Мониторинг

- [Основы Helm](docs/08-monitoring/helm-basics.md)
- [Prometheus и Grafana](docs/08-monitoring/prometheus-grafana.md)
- [Логи в Loki](docs/08-monitoring/loki-logs.md)

## Дополнительно

- [Samba: сетевое файловое хранилище](docs/09-optional-extras/samba-file-storage.md)

## Приложения

- [Чек-лист этапов](docs/99-appendix/roadmap-checklist.md)
- [Диагностика сети (только локальное железо)](docs/99-appendix/troubleshooting-networking.md)
- [Глоссарий](docs/99-appendix/glossary.md)

Готовые манифесты: [examples/wordpress](examples/wordpress/).

[На главную](../README.ru.md)
