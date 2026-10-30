# Довідник: маніфест бази даних (`db.yaml`)

Покрокові нотатки до кожного поля [`examples/wordpress/db.yaml`](../../../examples/wordpress/db.yaml): Deployment MySQL із постійним сховищем і Service типу ClusterIP. Користуйтеся ним, змінюючи облікові дані, версію, сховище чи ресурси.

## Deployment

| Поле | Що робить | Коли змінювати |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-db` | Назва Deployment | Для кожного проєкту |
| `strategy.type: Recreate` | Зупиняє старий под перед запуском нового. Два процеси MySQL на одному каталозі даних пошкоджують його; `RollingUpdate` за замовчуванням ненадовго запустив би обидва | Залишайте |
| `selector` / `template.labels: app: <PROJECT_NAME>-db` | Зв'язує под із Deployment і Service | Мають збігатися між собою та із селектором Service символ у символ |
| `image: mysql:8.4` | Версія MySQL. Фіксуйте її: зміна основної версії на наявному каталозі даних призводить до збою запуску | Оновлюйте свідомо, після дампа |
| `MYSQL_ROOT_PASSWORD` (із Secret) | Пароль root, що задається лише під час першої ініціалізації | Подальша зміна в маніфесті **не** змінює збережений пароль; використовуйте `ALTER USER` |
| `MYSQL_DATABASE` (із Secret) | База даних, що створюється під час першого запуску | Має збігатися з `DB_NAME` у `wp-config.php` і з назвою, яку використовують при імпорті дампів |
| `args: --character-set-server=utf8mb4 --collation-server=utf8mb4_general_ci` | Повний Unicode як кодування за замовчуванням (емодзі, 4-байтові символи); `_ci` = порівняння без урахування регістру | Підлаштуйте під колацію імпортованого дампа |
| `containerPort: 3306` | Лише документація | Ніколи |
| `resources.requests/limits` | Підказка планувальнику та обмеження пам'яті; `limits.memory` призводить до OOM-kill пода при перевищенні | Налаштовуйте під розмір проєкту (див. [контрольний список для кількох проєктів](../multi-project-checklist.md)) |

Значення змінних середовища беруться із Secret (`secretKeyRef`), тож паролі не потрапляють у Git:

```bash
kubectl -n <PROJECT_NAME> create secret generic <PROJECT_NAME>-secret \
  --from-literal=DB_ROOT_PASSWORD='<DB_PASSWORD>' --from-literal=DB_NAME='<DB_NAME>'
```

Значення Secret лише закодовані в base64, але не зашифровані; вони захищають від випадкових комітів, а не від будь-кого з доступом до кластера.

## Збереження даних

```yaml
volumeMounts:
- name: mysql-storage
  mountPath: /var/lib/mysql
volumes:
- name: mysql-storage
  hostPath:
    path: /home/<SERVER_USER>/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/mysql-data
    type: DirectoryOrCreate
```

> **Попередження:** без цього тому (або якщо `mountPath` не дорівнює точно `/var/lib/mysql`) MySQL пише в тимчасовий шар контейнера. Будь-яке перестворення пода (`rollout restart`, оновлення образу, перезавантаження вузла, збій) стирає всі дані. Це найруйнівніша помилка у всій конфігурації.

Примітки:
- Каталог даних має бути порожнім під час першого запуску; MySQL відмовляється ініціалізуватися поверх файлів, створених не ним.
- Кожному проєкту потрібен власний каталог `mysql-data`. Спільний каталог для кількох проєктів пошкоджує обидва.
- Виключіть `k8s-local/` з Git; робіть резервні копії через `mysqldump`, а не копіюванням робочого каталогу.

## Service

| Поле | Що робить | Коли змінювати |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-db-service` | DNS-ім'я, що використовується як хост БД: `DB_HOST` у `wp-config.php` і `PMA_HOST` у phpMyAdmin. З інших namespaces: `<PROJECT_NAME>-db-service.<PROJECT_NAME>.svc.cluster.local` | Для кожного проєкту; ніколи не називайте просто `db` |
| `selector: app: <PROJECT_NAME>-db` | Поди за Service | Має збігатися з мітками подів |
| `port` / `targetPort: 3306` | Порт Service і порт контейнера | Рідко |

Лише ClusterIP: база даних недоступна ззовні кластера, і це задумано. Для разового зовнішнього клієнта використовуйте `kubectl port-forward`:

```bash
kubectl -n <PROJECT_NAME> port-forward svc/<PROJECT_NAME>-db-service 3306:3306
```

## Перевірка

```bash
kubectl -n <PROJECT_NAME> get pods -l app=<PROJECT_NAME>-db
kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-db -- \
  sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"'
ls ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/mysql-data | head
```

Далі: [Маніфест phpMyAdmin](phpmyadmin-manifest.md)
