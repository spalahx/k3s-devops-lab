# Справочник: манифест phpMyAdmin (`phpmyadmin.yaml`)

Разбор полей [`examples/wordpress/phpmyadmin.yaml`](../../../examples/wordpress/phpmyadmin.yaml): веб-интерфейс к БД проекта на отдельном домене. Пропустите его, если хватает `kubectl exec` и `mysql`, и не публикуйте на сервере, доступном из интернета.

## Deployment

| Поле | Что делает | Когда менять |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-phpmyadmin` | Имя Deployment | Для каждого проекта |
| `selector` / `labels: app: <PROJECT_NAME>-phpmyadmin` | Связывает Deployment, под и Service | Должны совпадать друг с другом и с selector Service |
| `image: phpmyadmin:5` | Официальный образ «всё в одном» (веб-сервер внутри; отдельный Nginx не нужен) | Обновите минорную версию при необходимости |
| `PMA_HOST` | Сервер БД для подключения | Должен равняться `metadata.name` Service БД (`<PROJECT_NAME>-db-service`), включая регистр. Резолвится DNS кластера; не используйте IP и `localhost` |
| `PMA_ABSOLUTE_URI` | Публичный адрес, по которому phpMyAdmin считает себя доступным | Реальный HTTPS-домен с `/` в конце. Traefik завершает TLS, под видит обычный HTTP; без этого cookie отклоняются и сессия постоянно сбрасывается |
| `PMA_STORAGE: ""` | Отключает configuration storage (закладки, история), которому нужны дополнительные таблицы | Уберите, если создали эти таблицы |
| `containerPort: 80` | Только документация | Не менять |
| `resources.limits.memory` | Лимит, чтобы тяжёлый запрос не задушил другие проекты | Увеличьте для больших импортов |

Вход через форму: пользователь `root`, пароль `DB_ROOT_PASSWORD` из Secret проекта. Пароль намеренно не прописан в этом манифесте; для более строгого доступа создайте отдельного пользователя MySQL вместо root.

## Service

| Поле | Что делает |
|---|---|
| `metadata.name: <PROJECT_NAME>-phpmyadmin-svc` | Backend, на который ссылается Ingress |
| `selector: app: <PROJECT_NAME>-phpmyadmin` | Метка пода |
| `port: 80` / `targetPort: 80` | Порт Service и порт веб-сервера в образе |

## Ingress

| Поле | Что делает | Когда менять |
|---|---|---|
| `router.entrypoints: web,websecure` | Обслуживать HTTP и HTTPS | Только `websecure` для HTTPS-only |
| `router.tls: "true"` | TLS с сертификатом Traefik по умолчанию | Настройка настоящего сертификата |
| `host: <PROJECT_NAME>-pma.<DOMAIN_BASE>` | Домен админки; должен совпадать с `PMA_ABSOLUTE_URI` и записью в `/etc/hosts` на клиенте | Для каждого проекта, уникальный |
| `backend.service` | Должен равняться Service выше | При переименовании Service |

> **Warning:** phpMyAdmin с доступом root — лакомая цель. Делайте домен разрешимым только в локальной сети или через туннель ([VPS-шлюз](../../06-remote-access/vps-gateway-setup.md)) и удаляйте Deployment, когда он не нужен: `kubectl -n <PROJECT_NAME> delete -f phpmyadmin.yaml`.

## Частые ошибки

| Симптом | Причина |
|---|---|
| `Cannot connect: invalid settings` | `PMA_HOST` отличается от имени Service БД |
| `Access denied for user 'root'` | Введённый пароль отличается от заданного при первой инициализации БД |
| Цикл редиректов или «сброс входа» | `PMA_ABSOLUTE_URI` не задан или с `http://` |
| 404 от Traefik | host в Ingress не совпадает с запрошенным доменом |

## Verify

```bash
kubectl -n <PROJECT_NAME> get pods -l app=<PROJECT_NAME>-phpmyadmin
curl -kI https://<PROJECT_NAME>-pma.<DOMAIN_BASE>/
```

Next: [Миграция медиа и базы данных](../media-and-database-migration.md)
