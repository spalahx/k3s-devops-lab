# Угоди про каталоги та іменування: код і маніфести

Описує розкладку з двох репозиторіїв на сервері: код проєктів у `~/workspace`, маніфести Kubernetes у `~/k8s-infrastructure`. Скористайтеся нею перед розгортанням першого проєкту; пропустіть лише якщо у вас один проєкт, а маніфести лежать у його власному репозиторії.

## Розкладка

```
~/workspace/<PROJECT_GROUP>/              # лише код (PHP/JS/теми), один Git-репозиторій на проєкт
├── <PROJECT_NAME>/
│   ├── k8s-local/                        # лише локально: конфіг nginx, mysql-data (виключено з Git)
│   └── ...
└── <OTHER_PROJECT>/

~/k8s-infrastructure/                     # лише маніфести, власний Git-репозиторій
├── system/                               # на рівні кластера: налаштування Traefik, моніторинг
│   ├── ingress/
│   └── monitoring/
├── ai-models/                            # ізольовані AI-навантаження
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

| Каталог | Що містить | Як часто змінюється |
|---|---|---|
| `~/workspace/...` | Код застосунку, історія в Git проєкту | Багато разів на день |
| `~/k8s-infrastructure/system/` | Конфігурація кластера, спільна для всіх проєктів | Рідко |
| `~/k8s-infrastructure/ai-models/` | Локальні LLM-навантаження, ізольовані від веб-проєктів | Рідко |
| `~/k8s-infrastructure/projects/` | По одному каталогу на кожен розгорнутий проєкт | Коли змінюються імена хостів, ресурси або образи |

Причини розділення: код і конфігурація середовища виконання змінюються з різною швидкістю, належать різним репозиторіям і власникам, а маніфести можуть містити деталі інфраструктури (імена хостів, розміри ресурсів), яким не місце в репозиторії застосунку.

## Правила іменування

1. Назви каталогів проєктів **однакові** в обох деревах (`~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>` і `~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>`). Shell-хелпери на кшталт `kstart`/`kstop` (див. [аліаси K3s](../03-containers-and-k3s/k3s-productivity-aliases.md)) покладаються на це, щоб знайти маніфести за короткою назвою проєкту.
2. Кожна назва об'єкта містить префікс проєкту; ніколи не використовуйте голі `db`, `app`, `redis`:

   | Об'єкт | Назва |
   |---|---|
   | Namespace | `<PROJECT_NAME>` |
   | Deployments | `<PROJECT_NAME>-app`, `<PROJECT_NAME>-db`, `<PROJECT_NAME>-phpmyadmin` |
   | Services | `<PROJECT_NAME>-service`, `<PROJECT_NAME>-db-service`, `<PROJECT_NAME>-phpmyadmin-svc` |
   | Мітки | `app: <PROJECT_NAME>`, `app: <PROJECT_NAME>-db` |
   | Імена хостів | `<PROJECT_NAME>.<DOMAIN_BASE>`, `<PROJECT_NAME>-pma.<DOMAIN_BASE>` |
   | Локальний образ | `<PROJECT_NAME>-php:latest` |

3. В іменах файлів порядок не закладається. `kubectl apply -R -f <dir>` застосовує все одразу; застосунок, що стартував раніше за базу даних, просто перезапускається, доки БД не буде готова.

## Один файл чи кілька

| Варіант | Коли використовувати |
|---|---|
| Один `app.yaml` (об'єкти розділені `---`) | Проєкт з одним компонентом |
| `deployment.yaml` / `service.yaml` / `ingress.yaml` | Група невеликих простих проєктів |
| `db.yaml`, `phpmyadmin.yaml`, `app.yaml` | Проєкт з кількома компонентами (WordPress + БД + адмінка); дозволяє перезапустити або видалити один компонент |

Kubernetes обробляє всі варіанти однаково. Готові файли для WordPress: [`examples/wordpress/`](../../examples/wordpress/).

## Namespaces

Один namespace на проєкт: `kubectl create namespace <PROJECT_NAME>`. Namespace забезпечує ізоляцію імен (у двох проєктах може бути Service з назвою `db`), очищення однією командою (`kubectl delete namespace`) і квоти для кожного проєкту. Вказуйте `metadata.namespace` у кожному маніфесті, щоб `kubectl apply -f` не залежав від поточного контексту. Компоненти рівня кластера (Traefik, моніторинг) лишаються у власних namespaces і тут не керуються.

## Що де змінювати

| Завдання | Розташування |
|---|---|
| Редагування коду застосунку | `~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/` |
| Зміна імені хоста, реплік, ресурсів | `~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>/app.yaml` |
| Зміна налаштувань БД | `.../db.yaml` |
| Глобальні Traefik / моніторинг | `~/k8s-infrastructure/system/` |
| Локальна LLM | `~/k8s-infrastructure/ai-models/ollama/` |

## Створення структури

```bash
mkdir -p ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/{nginx,mysql-data}
mkdir -p ~/k8s-infrastructure/{system/{ingress,monitoring},ai-models/ollama}
mkdir -p ~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>
cd ~/k8s-infrastructure && git init
```

Щоб локальні дані не потрапляли в репозиторій коду, не чіпаючи його спільний `.gitignore`:

```bash
printf 'k8s-local/\nwp-cli.phar\n*.sql\n' >> ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/.git/info/exclude
```

> **Попередження:** редагування коду в `~/workspace` саме по собі не змінює запущений контейнер. Якщо код змонтовано через `hostPath`, зміна видна одразу (перезапуск потрібен, лише якщо її кешує opcache); якщо код вбудовано в образ, потрібно перезібрати образ і виконати `kubectl rollout restart`.

## Перевірка

```bash
ls ~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>/
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME> && git status --short   # k8s-local/ не має відображатися
```

Якщо `kubectl apply -R -f <dir>` виводить `no objects passed to apply`, у каталозі немає файлів `.yaml` або шлях неправильний.

Далі: [Загальний покроковий посібник із розгортання](generic-deployment-walkthrough.md)
