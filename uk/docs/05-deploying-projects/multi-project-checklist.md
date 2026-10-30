# Кілька проєктів одночасно

Контрольний список для додавання другого й кожного наступного проєкту на один вузол K3s без конфліктів. Застосовуйте його щоразу перед `kubectl apply` нового проєкту.

## Контрольний список для кожного проєкту

| # | Пункт | Правило |
|---|---|---|
| 1 | Namespace | Один на проєкт: `kubectl create namespace <PROJECT_NAME>`; `metadata.namespace` вказано в кожному маніфесті |
| 2 | Назви об'єктів | Префікс проєкту в Deployments, Services, Ingresses (`<PROJECT_NAME>-db-service`, ніколи не `db`) |
| 3 | Мітки | `app: <PROJECT_NAME>[-component]` унікальні; селектори збігаються з мітками подів |
| 4 | Імена хостів | `<PROJECT_NAME>.<DOMAIN_BASE>` і `<PROJECT_NAME>-pma.<DOMAIN_BASE>` унікальні; додані в `/etc/hosts` клієнта (або в DNS) |
| 5 | Хост БД | `DB_HOST` і `PMA_HOST` = Service БД цього проєкту |
| 6 | hostPath | Власні `k8s-local/mysql-data` і каталог коду для кожного проєкту; жодні два поди не монтують один каталог даних MySQL |
| 7 | Локальний образ | Унікальний тег `<PROJECT_NAME>-php:latest`, імпортований у containerd |
| 8 | Secret | Власний `<PROJECT_NAME>-secret` з окремим паролем БД |
| 9 | Порти | Без `hostPort`/`NodePort`, якщо це не потрібно; див. нижче |
| 10 | Ресурси | `requests`/`limits` задано для кожного контейнера |

## Порти

Увесь HTTP-трафік іде через Traefik на портах 80/443 і маршрутизується за іменем хоста, тому проєктам не потрібні власні публічні порти. Уникайте `hostPort` і `type: NodePort` для веб-застосунків. Якщо сервіс має бути доступний напряму (SSH до пода, клієнт бази даних), призначайте NodePort із діапазону 30000-32767 і фіксуйте їх в одному списку, щоб вони ніколи не перетиналися:

| Проєкт | Service | NodePort |
|---|---|---|
| `<PROJECT_NAME>` | `<PROJECT_NAME>-db-service` | `30001` (приклад) |

Для разового доступу краще використовувати `kubectl port-forward`: він нічого не відкриває назавжди.

## Обмеження ресурсів

Один вузол ділить RAM і CPU між усіма проєктами, а один некерований MySQL може спровокувати OOM killer вузла для всіх.

```yaml
resources:
  requests: { cpu: 100m, memory: 256Mi }   # резервується для планування
  limits:   { memory: 1Gi }                # жорстке обмеження: перевищення завершує контейнер
```

За бажанням можна обмежити весь namespace:

```bash
kubectl -n <PROJECT_NAME> create quota <PROJECT_NAME>-quota --hard=requests.memory=2Gi,limits.memory=4Gi,pods=10
```

Поди без заданих requests/limits після цього відхиляються, тож спершу задайте їх у кожному маніфесті. Перевірка фактичного використання:

```bash
kubectl top pods -A          # потрібен metrics-server (входить до складу K3s)
```

## Доступ між namespaces (інтеграційне тестування)

Services доступні з будь-якого namespace за повними DNS-іменами:

```
<service>.<namespace>.svc.cluster.local
```

Приклад: застосунок проєкту A звертається до API проєкту B, або тестовий под звертається до БД:

```bash
kubectl -n <PROJECT_NAME> run dns-test --rm -it --image=busybox:1.36 --restart=Never -- \
  wget -qO- http://<OTHER_PROJECT>-service.<OTHER_PROJECT>.svc.cluster.local/
```

Усередині одного namespace достатньо короткої назви (`<PROJECT_NAME>-db-service`). Повну форму використовуйте лише для навмисних зв'язків між проєктами; за замовчуванням namespaces не ізольовані на рівні мережі. Якщо проєкт не має бути доступним для інших, обмежте доступ через `NetworkPolicy`.

## Очищення

```bash
kubectl delete namespace <PROJECT_NAME>                    # усі об'єкти проєкту
sudo rm -rf ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/mysql-data   # файли бази даних (незворотно)
sudo k3s ctr images rm docker.io/library/<PROJECT_NAME>-php:latest
docker rmi <PROJECT_NAME>-php:latest
```

Потім видаліть рядки з `/etc/hosts` і каталог маніфестів у `~/k8s-infrastructure/projects/`. Видалення namespace не видаляє дані `hostPath`; перед видаленням зробіть останній `mysqldump`.

## Перевірка

```bash
kubectl get ns
kubectl get ingress -A          # усі хости мають відрізнятися
kubectl get svc -A | grep -c db # кожен проєкт має власний Service БД у власному namespace
kubectl top nodes
```

Далі: [Контрольний список дорожньої карти](../99-appendix/roadmap-checklist.md)
