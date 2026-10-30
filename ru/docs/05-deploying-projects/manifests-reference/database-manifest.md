# Справочник: манифест базы данных (`db.yaml`)

Разбор полей [`examples/wordpress/db.yaml`](../../../examples/wordpress/db.yaml): Deployment MySQL с постоянным хранилищем и Service типа ClusterIP. Используйте при смене учётных данных, версии, хранилища или ресурсов.

## Deployment

| Поле | Что делает | Когда менять |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-db` | Имя Deployment | Для каждого проекта |
| `strategy.type: Recreate` | Сначала останавливает старый под, потом запускает новый. Два процесса MySQL на одном каталоге данных портят его; `RollingUpdate` по умолчанию на время запустил бы оба | Оставить |
| `selector` / `template.labels: app: <PROJECT_NAME>-db` | Связывает под с Deployment и Service | Должны совпадать друг с другом и с selector Service символ в символ |
| `image: mysql:8.4` | Версия MySQL. Фиксируйте: смена мажорной версии на существующем каталоге данных не запустится | Обновляйте осознанно, после дампа |
| `MYSQL_ROOT_PASSWORD` (из Secret) | Пароль root, задаётся только при первой инициализации | Последующая правка манифеста **не** меняет сохранённый пароль; используйте `ALTER USER` |
| `MYSQL_DATABASE` (из Secret) | БД, создаваемая при первом старте | Должна совпадать с `DB_NAME` в `wp-config.php` и именем БД при импорте дампа |
| `args: --character-set-server=utf8mb4 --collation-server=utf8mb4_general_ci` | Кодировка по умолчанию с полным Unicode (эмодзи, 4-байтовые символы); `_ci` — сравнение без учёта регистра | Согласуйте с collation импортируемого дампа |
| `containerPort: 3306` | Только документация | Не менять |
| `resources.requests/limits` | Подсказка планировщику и лимит памяти; превышение `limits.memory` убивает под (OOM) | Подберите под размер проекта (см. [чек-лист](../multi-project-checklist.md)) |

Значения env берутся из Secret (`secretKeyRef`), чтобы пароль не попадал в Git:

```bash
kubectl -n <PROJECT_NAME> create secret generic <PROJECT_NAME>-secret \
  --from-literal=DB_ROOT_PASSWORD='<DB_PASSWORD>' --from-literal=DB_NAME='<DB_NAME>'
```

Значения Secret лишь закодированы в base64, а не зашифрованы: это защита от случайного коммита, а не от человека с доступом к кластеру.

## Постоянное хранилище

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

> **Warning:** без этого тома (или с `mountPath`, не равным точно `/var/lib/mysql`) MySQL пишет в эфемерный слой контейнера. Любое пересоздание пода (`rollout restart`, обновление образа, перезагрузка узла, сбой) стирает все данные. Это самая разрушительная ошибка во всей схеме.

Примечания:
- При первом старте каталог данных должен быть пустым; MySQL не инициализируется поверх чужих файлов.
- У каждого проекта свой каталог `mysql-data`. Общий каталог у двух проектов портит оба.
- Исключите `k8s-local/` из Git; резервные копии делайте через `mysqldump`, а не копированием работающего каталога.

## Service

| Поле | Что делает | Когда менять |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-db-service` | DNS-имя как хост БД: `DB_HOST` в `wp-config.php` и `PMA_HOST` в phpMyAdmin. Из других namespace: `<PROJECT_NAME>-db-service.<PROJECT_NAME>.svc.cluster.local` | Для каждого проекта; не называйте просто `db` |
| `selector: app: <PROJECT_NAME>-db` | Поды за Service | Должен совпадать с метками пода |
| `port` / `targetPort: 3306` | Порт Service и контейнера | Редко |

Только ClusterIP: БД недоступна снаружи кластера, так и задумано. Для разового внешнего клиента используйте `kubectl port-forward`:

```bash
kubectl -n <PROJECT_NAME> port-forward svc/<PROJECT_NAME>-db-service 3306:3306
```

## Verify

```bash
kubectl -n <PROJECT_NAME> get pods -l app=<PROJECT_NAME>-db
kubectl -n <PROJECT_NAME> exec deploy/<PROJECT_NAME>-db -- \
  sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"'
ls ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/mysql-data | head
```

Next: [Манифест phpMyAdmin](phpmyadmin-manifest.md)
