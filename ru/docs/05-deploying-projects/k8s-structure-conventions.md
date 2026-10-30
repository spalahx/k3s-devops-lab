# Структура каталогов и правила именования: код и манифесты

Описывает раскладку из двух репозиториев на сервере: код проектов в `~/workspace`, манифесты Kubernetes в `~/k8s-infrastructure`. Применяйте перед развёртыванием первого проекта; пропустите, только если у вас один проект и манифесты лежат в его собственном репозитории.

## Раскладка

```
~/workspace/<PROJECT_GROUP>/              # только код (PHP/JS/темы), один Git-репозиторий на проект
├── <PROJECT_NAME>/
│   ├── k8s-local/                        # только локально: конфиг nginx, mysql-data (вне Git)
│   └── ...
└── <OTHER_PROJECT>/

~/k8s-infrastructure/                     # только манифесты, отдельный Git-репозиторий
├── system/                               # общее для кластера: настройки Traefik, мониторинг
│   ├── ingress/
│   └── monitoring/
├── ai-models/                            # изолированные ИИ-нагрузки
│   └── ollama/
└── projects/
    └── <PROJECT_GROUP>/
        ├── <PROJECT_NAME>/
        │   ├── db.yaml
        │   ├── phpmyadmin.yaml
        │   └── app.yaml
        └── <OTHER_PROJECT>/
            └── app.yaml
```

| Каталог | Содержимое | Как часто меняется |
|---|---|---|
| `~/workspace/...` | Код приложения, история в Git проекта | Много раз в день |
| `~/k8s-infrastructure/system/` | Настройки кластера, общие для всех проектов | Редко |
| `~/k8s-infrastructure/ai-models/` | Локальные LLM, изолированные от веб-проектов | Редко |
| `~/k8s-infrastructure/projects/` | Один каталог на каждый развёрнутый проект | При смене доменов, ресурсов, образов |

Причины разделения: код и параметры запуска меняются с разной скоростью, живут в разных репозиториях и у разных владельцев, а в манифестах могут быть детали инфраструктуры (домены, размеры ресурсов), которым не место в репозитории приложения.

## Правила именования

1. Имена каталогов проектов **одинаковы** в обоих деревьях (`~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>` и `~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>`). Shell-функции `kstart`/`kstop` (см. [алиасы K3s](../03-containers-and-k3s/k3s-productivity-aliases.md)) по короткому имени проекта находят манифесты именно благодаря этому.
2. Все имена объектов содержат префикс проекта; никаких «голых» `db`, `app`, `redis`:

   | Объект | Имя |
   |---|---|
   | Namespace | `<PROJECT_NAME>` |
   | Deployment | `<PROJECT_NAME>-app`, `<PROJECT_NAME>-db`, `<PROJECT_NAME>-phpmyadmin` |
   | Service | `<PROJECT_NAME>-service`, `<PROJECT_NAME>-db-service`, `<PROJECT_NAME>-phpmyadmin-svc` |
   | Labels | `app: <PROJECT_NAME>`, `app: <PROJECT_NAME>-db` |
   | Домены | `<PROJECT_NAME>.<DOMAIN_BASE>`, `<PROJECT_NAME>-pma.<DOMAIN_BASE>` |
   | Локальный образ | `<PROJECT_NAME>-php:latest` |

3. Порядок применения не зависит от имён файлов. `kubectl apply -R -f <каталог>` применяет всё сразу; приложение, стартовавшее раньше БД, просто перезапускается, пока БД не будет готова.

## Один файл или несколько

| Вариант | Когда использовать |
|---|---|
| Один `app.yaml` (объекты через `---`) | Проект из одного компонента |
| `deployment.yaml` / `service.yaml` / `ingress.yaml` | Группа небольших простых проектов |
| `db.yaml`, `phpmyadmin.yaml`, `app.yaml` | Проект из нескольких компонентов (WordPress + БД + админка БД): можно перезапускать или удалять компоненты по отдельности |

Kubernetes обрабатывает все варианты одинаково. Готовые файлы для WordPress: [`examples/wordpress/`](../../examples/wordpress/).

## Namespace

Один namespace на проект: `kubectl create namespace <PROJECT_NAME>`. Это даёт изоляцию имён (в двух проектах может быть Service `db`), удаление проекта одной командой (`kubectl delete namespace`) и квоты на проект. Указывайте `metadata.namespace` в каждом манифесте, чтобы `kubectl apply -f` не зависел от текущего контекста. Компоненты уровня кластера (Traefik, мониторинг) живут в своих namespace и здесь не управляются.

## Где что менять

| Задача | Место |
|---|---|
| Править код приложения | `~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/` |
| Сменить домен, реплики, ресурсы | `~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>/app.yaml` |
| Настройки БД | `.../db.yaml` |
| Глобальные Traefik / мониторинг | `~/k8s-infrastructure/system/` |
| Локальная LLM | `~/k8s-infrastructure/ai-models/ollama/` |

## Создание каркаса

```bash
mkdir -p ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/{nginx,mysql-data}
mkdir -p ~/k8s-infrastructure/{system/{ingress,monitoring},ai-models/ollama}
mkdir -p ~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>
cd ~/k8s-infrastructure && git init
```

Исключите локальные данные из репозитория кода, не трогая общий `.gitignore`:

```bash
printf 'k8s-local/\nwp-cli.phar\n*.sql\n' >> ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/.git/info/exclude
```

> **Warning:** правка кода в `~/workspace` сама по себе не меняет запущенный контейнер. Если код смонтирован через `hostPath`, изменения видны сразу (перезапуск нужен, только если их держит opcache); если код «запечён» в образ, нужно пересобрать образ и выполнить `kubectl rollout restart`.

## Verify

```bash
ls ~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>/
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME> && git status --short   # k8s-local/ не должен упоминаться
```

Сообщение `no objects passed to apply` у `kubectl apply -R -f <каталог>` значит, что в каталоге нет `.yaml`-файлов или путь неверный.

Next: [Пошаговое развёртывание проекта](generic-deployment-walkthrough.md)
