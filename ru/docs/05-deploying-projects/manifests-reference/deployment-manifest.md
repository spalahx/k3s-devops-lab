# Справочник: манифест приложения (`app.yaml`)

Разбор полей [`examples/wordpress/app.yaml`](../../../examples/wordpress/app.yaml): один под с PHP-FPM и Nginx, Service и Ingress для Traefik. Используйте при адаптации файла под новый проект.

Основные объекты: **Deployment** поддерживает N одинаковых подов; **Service** даёт им стабильное DNS-имя внутри кластера; **Ingress** связывает внешний домен с Service (обслуживается Traefik). Объекты в одном файле разделяются `---`.

## Deployment

| Поле | Что делает | Когда менять |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-app` | Имя Deployment; цель для `rollout restart` | Всегда задавать для проекта |
| `metadata.namespace` | Namespace объекта | Всегда = namespace проекта |
| `spec.replicas: 1` | Число подов. Оставьте 1: код и данные лежат на диске одного узла | Не менять на одноузловом сервере |
| `spec.selector.matchLabels` | Какими подами владеет Deployment | Должен точно совпадать с `template.metadata.labels`, иначе `apply` падает с `selector does not match template labels` |
| `template.metadata.labels: app: <PROJECT_NAME>` | Метка пода; по ней Service выбирает поды | Должна совпадать с `selector` у Service |
| `containers[php].image` | Образ PHP-FPM, собранный из Dockerfile проекта | Новое имя/тег образа |
| `imagePullPolicy: Never` | Не скачивать из реестра, брать локальный образ containerd | Убрать, если образ берётся из реестра |
| `workingDir: /var/www/html` | Рабочий каталог PHP-процесса | Редко |
| `ports.containerPort: 9000` | Только документация (порт FPM); ничего не открывает | Редко |
| `containers[nginx].image: nginx:alpine` | Стандартный Nginx | Зафиксируйте версию для воспроизводимости |
| `ports.containerPort: 80` | Только документация | Если Nginx слушает другой порт |
| `volumeMounts[code-volume]` | Каталог проекта в обоих контейнерах как `/var/www/html`; в Nginx только чтение | Путь должен совпадать с Dockerfile и `root` в `default.conf` |
| `volumeMounts[nginx-conf]` → `/etc/nginx/conf.d` | Монтирует каталог с конфигом сайта только на чтение | Только если переносите конфиг |

Оба контейнера делят одно сетевое пространство, поэтому Nginx обращается к PHP-FPM по `127.0.0.1:9000`.

## Тома (`hostPath`)

`hostPath` подключает каталог с диска узла внутрь контейнера. Это самый простой тип тома; он привязывает под к этому серверу, что допустимо для одного узла.

| Том | `path` | `type` |
|---|---|---|
| `code-volume` | `/home/<SERVER_USER>/workspace/<PROJECT_GROUP>/<PROJECT_NAME>` | `DirectoryOrCreate` |
| `nginx-conf` | `.../<PROJECT_NAME>/k8s-local/nginx` | `Directory` |

- `Directory`: путь обязан существовать, иначе под остаётся в `Pending` (в `kubectl describe pod` — `hostPath type check failed`). Используйте для того, что должно быть создано заранее.
- `DirectoryOrCreate`: Kubernetes создаст пустой каталог, если его нет. Удобно, но опечатка молча даёт пустой корень сайта.
- Монтируйте только каталог с одним конфигом, а не всё дерево конфигов Nginx из репозитория.
- TLS завершается на Traefik, поэтому сертификаты в Nginx не монтируются.

## Service

| Поле | Что делает | Когда менять |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-service` | DNS-имя в кластере `<PROJECT_NAME>-service.<PROJECT_NAME>.svc.cluster.local` | Для каждого проекта; в Ingress указывать то же имя |
| `spec.selector: app: <PROJECT_NAME>` | Поды, получающие трафик | Должен совпадать с метками пода, иначе у Service нет endpoints |
| `ports.port: 80` | Порт Service | Если другие поды обращаются к другому порту |
| `ports.targetPort: 80` | Порт контейнера (Nginx), куда идёт трафик | Если Nginx слушает другой порт |

Тип по умолчанию `ClusterIP`: доступен только внутри кластера; снаружи трафик приходит через Ingress.

## Ingress

| Поле | Что делает | Когда менять |
|---|---|---|
| `traefik.../router.entrypoints: web,websecure` | Обслуживать HTTP (80) и HTTPS (443) entrypoints Traefik | Только `websecure`, чтобы запретить HTTP |
| `traefik.../router.tls: "true"` | Включает TLS; используется самоподписанный сертификат Traefik (предупреждение в браузере) | Добавьте блок `tls:`/cert resolver для настоящего сертификата |
| `rules[0].host: <PROJECT_NAME>.<DOMAIN_BASE>` | Домен проекта; два Ingress с одним host конфликтуют | Всегда уникальный для проекта |
| `paths: / (Prefix)` | Всё под `/` | Только для публикации подпути |
| `backend.service.name/port` | Целевой Service и порт | Должны совпадать с именем и `port` Service выше |

## Verify

```bash
kubectl apply --dry-run=server -f app.yaml
kubectl -n <PROJECT_NAME> get endpoints <PROJECT_NAME>-service     # должен быть IP пода
kubectl -n <PROJECT_NAME> describe ingress <PROJECT_NAME>-ingress
```

Пустой `ENDPOINTS` означает, что selector и метки пода различаются.

Next: [Манифест базы данных](database-manifest.md)
