# Несколько проектов на одном сервере

Чек-лист добавления второго и последующих проектов на один узел K3s без конфликтов. Проходите его перед каждым `kubectl apply` нового проекта.

## Чек-лист на проект

| # | Пункт | Правило |
|---|---|---|
| 1 | Namespace | Свой на проект: `kubectl create namespace <PROJECT_NAME>`; `metadata.namespace` задан в каждом манифесте |
| 2 | Имена объектов | Префикс проекта у Deployment, Service, Ingress (`<PROJECT_NAME>-db-service`, но не `db`) |
| 3 | Метки | `app: <PROJECT_NAME>[-component]` уникальны; selector совпадает с метками пода |
| 4 | Домены | `<PROJECT_NAME>.<DOMAIN_BASE>` и `<PROJECT_NAME>-pma.<DOMAIN_BASE>` уникальны; добавлены в `/etc/hosts` клиента (или DNS) |
| 5 | Хост БД | `DB_HOST` и `PMA_HOST` = Service БД этого проекта |
| 6 | hostPath | Свои `k8s-local/mysql-data` и каталог кода на проект; два пода не монтируют один каталог данных MySQL |
| 7 | Локальный образ | Уникальный тег `<PROJECT_NAME>-php:latest`, импортирован в containerd |
| 8 | Secret | Свой `<PROJECT_NAME>-secret` со своим паролем БД |
| 9 | Порты | Без `hostPort`/`NodePort`, пока не нужно; см. ниже |
| 10 | Ресурсы | `requests`/`limits` у каждого контейнера |

## Порты

Весь HTTP идёт через Traefik на 80/443 и маршрутизируется по домену, поэтому собственные внешние порты проектам не нужны. Не используйте `hostPort` и `type: NodePort` для веб-приложений. Если сервис должен быть доступен напрямую (SSH в под, клиент БД), выдавайте NodePort из диапазона 30000-32767 и ведите единый список, чтобы они не пересекались:

| Проект | Service | NodePort |
|---|---|---|
| `<PROJECT_NAME>` | `<PROJECT_NAME>-db-service` | `30001` (пример) |

Для разового доступа лучше `kubectl port-forward`: он ничего не открывает навсегда.

## Лимиты ресурсов

Один узел делит RAM и CPU между всеми проектами, а один разросшийся MySQL может вызвать OOM killer и для остальных.

```yaml
resources:
  requests: { cpu: 100m, memory: 256Mi }   # резерв для планировщика
  limits:   { memory: 1Gi }                # жёсткий предел: превышение убивает контейнер
```

При желании ограничьте namespace целиком:

```bash
kubectl -n <PROJECT_NAME> create quota <PROJECT_NAME>-quota --hard=requests.memory=2Gi,limits.memory=4Gi,pods=10
```

После этого поды без requests/limits отклоняются, поэтому сначала задайте их во всех манифестах. Фактическое потребление:

```bash
kubectl top pods -A          # нужен metrics-server (входит в K3s)
```

## Доступ между namespace (интеграционное тестирование)

Service доступны из любого namespace по полному DNS-имени:

```
<service>.<namespace>.svc.cluster.local
```

Пример: приложение проекта A обращается к API проекта B или тестовый под — к БД:

```bash
kubectl -n <PROJECT_NAME> run dns-test --rm -it --image=busybox:1.36 --restart=Never -- \
  wget -qO- http://<OTHER_PROJECT>-service.<OTHER_PROJECT>.svc.cluster.local/
```

Внутри одного namespace достаточно короткого имени (`<PROJECT_NAME>-db-service`). Полную форму используйте только для намеренных связей между проектами; по умолчанию сетевой изоляции между namespace нет. Если проект не должен быть доступен другим, ограничьте его через `NetworkPolicy`.

## Очистка

```bash
kubectl delete namespace <PROJECT_NAME>                    # все объекты проекта
sudo rm -rf ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/mysql-data   # файлы БД (необратимо)
sudo k3s ctr images rm docker.io/library/<PROJECT_NAME>-php:latest
docker rmi <PROJECT_NAME>-php:latest
```

Затем удалите строки из `/etc/hosts` и каталог манифестов в `~/k8s-infrastructure/projects/`. Удаление namespace не удаляет данные `hostPath`; перед их удалением сделайте финальный `mysqldump`.

## Verify

```bash
kubectl get ns
kubectl get ingress -A          # все host должны различаться
kubectl get svc -A | grep -c db # у каждого проекта свой Service БД в своём namespace
kubectl top nodes
```

Next: [Чек-лист дорожной карты](../99-appendix/roadmap-checklist.md)
