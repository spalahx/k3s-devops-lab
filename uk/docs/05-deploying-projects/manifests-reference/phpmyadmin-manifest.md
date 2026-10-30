# Довідник: маніфест phpMyAdmin (`phpmyadmin.yaml`)

Покрокові нотатки до кожного поля [`examples/wordpress/phpmyadmin.yaml`](../../../examples/wordpress/phpmyadmin.yaml): вебінтерфейс бази даних проєкту на окремому імені хоста. Пропустіть його для проєктів, де достатньо `kubectl exec` і `mysql`, і ніколи не відкривайте його на сервері, доступному з інтернету.

## Deployment

| Поле | Що робить | Коли змінювати |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-phpmyadmin` | Назва Deployment | Для кожного проєкту |
| `selector` / `labels: app: <PROJECT_NAME>-phpmyadmin` | Зв'язують Deployment, под і Service | Мають збігатися між собою та із селектором Service |
| `image: phpmyadmin:5` | Офіційний образ «все в одному» (вебсервер включено; сайдкар Nginx не потрібен) | Зафіксуйте новіший мінорний випуск, якщо потрібно |
| `PMA_HOST` | Сервер бази даних, до якого підключатися | Має дорівнювати `metadata.name` Service БД (`<PROJECT_NAME>-db-service`), включно з регістром. DNS кластера розв'язує його; не використовуйте IP чи `localhost` |
| `PMA_ABSOLUTE_URI` | Публічна URL-адреса, за якою, на думку phpMyAdmin, він доступний | Має бути справжнім HTTPS-іменем хоста з кінцевим `/`. Traefik завершує TLS, тому под бачить звичайний HTTP; без цього cookie входу відхиляються, і сесія постійно скидається |
| `PMA_STORAGE: ""` | Вимикає функцію сховища конфігурації (закладки, історія), якій потрібні додаткові таблиці | Приберіть, якщо ви створюєте ці таблиці |
| `containerPort: 80` | Лише документація | Ніколи |
| `resources.limits.memory` | Обмеження, щоб важкий запит не позбавляв ресурсів інші проєкти | Збільште для великих імпортів |

Вхід виконується через форму: користувач `root`, пароль `DB_ROOT_PASSWORD` із Secret проєкту. Пароль свідомо не вказано в цьому маніфесті; щоб ще більше обмежити доступ, створіть окремого користувача MySQL замість root.

## Service

| Поле | Що робить |
|---|---|
| `metadata.name: <PROJECT_NAME>-phpmyadmin-svc` | Бекенд, на який посилається Ingress |
| `selector: app: <PROJECT_NAME>-phpmyadmin` | Мітка пода |
| `port: 80` / `targetPort: 80` | Порт Service і порт вебсервера образу |

## Ingress

| Поле | Що робить | Коли змінювати |
|---|---|---|
| `router.entrypoints: web,websecure` | Обслуговувати на точках входу HTTP і HTTPS | `websecure` лише для режиму тільки HTTPS |
| `router.tls: "true"` | TLS із сертифікатом Traefik за замовчуванням | Налаштування справжнього сертифіката |
| `host: <PROJECT_NAME>-pma.<DOMAIN_BASE>` | Ім'я хоста адмінки; має збігатися з `PMA_ABSOLUTE_URI` і записом у `/etc/hosts` на клієнті | Для кожного проєкту, унікальне |
| `backend.service` | Має дорівнювати Service вище | При перейменуванні Service |

> **Попередження:** phpMyAdmin із доступом root — дуже приваблива ціль для атак. Робіть ім'я хоста доступним лише у вашій локальній мережі або через тунель ([VPS-шлюз](../../06-remote-access/vps-gateway-setup.md)) і видаляйте Deployment, коли він не потрібен: `kubectl -n <PROJECT_NAME> delete -f phpmyadmin.yaml`.

## Типові помилки

| Симптом | Причина |
|---|---|
| `Cannot connect: invalid settings` | `PMA_HOST` відрізняється від назви Service БД |
| `Access denied for user 'root'` | Введений пароль відрізняється від заданого під час першої ініціалізації БД |
| Цикл перенаправлень або «вхід скидається» | `PMA_ABSOLUTE_URI` відсутній або починається з `http://` |
| 404 від Traefik | Хост в Ingress не збігається із запитаним іменем хоста |

## Перевірка

```bash
kubectl -n <PROJECT_NAME> get pods -l app=<PROJECT_NAME>-phpmyadmin
curl -kI https://<PROJECT_NAME>-pma.<DOMAIN_BASE>/
```

Далі: [Міграція медіафайлів і бази даних](../media-and-database-migration.md)
