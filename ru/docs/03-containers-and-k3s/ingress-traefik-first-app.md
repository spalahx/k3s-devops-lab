# Ingress через Traefik и первое приложение

Разворачивает временное приложение Nginx и публикует его как `http://<PROJECT_NAME>.<DOMAIN_BASE>` через ingress-контроллер Traefik, который K3s ставит по умолчанию. Выполняется один раз, чтобы убедиться, что вся цепочка (Deployment, Service, Ingress, DNS на ноутбуке) работает, прежде чем разворачивать реальные проекты.

## Как это работает

```
браузер --> <SERVER_IP>:80 --> Traefik (kube-system) --> правило Ingress (заголовок Host) --> Service --> Pod
```

| Объект | Роль |
|---|---|
| Deployment | Поддерживает N реплик Pod в рабочем состоянии |
| Service | Постоянный внутренний адрес для Pod, выбранных по label-селектору |
| Ingress | Правило «запросы для хоста X идут в Service Y»; Traefik подхватывает его автоматически |

- K3s привязывает Traefik к портам 80/443 узла (сервис `traefik`, тип `LoadBalancer`, обслуживается встроенным ServiceLB), поэтому все проекты делят один IP и порт; маршрутизация идёт по заголовку `Host`.
- K3s помечает Traefik как ingress class по умолчанию, поэтому `ingressClassName` можно не указывать.
- На самом Traefik ничего настраивать не нужно.

## 1. Выбор имени хоста

`<PROJECT_NAME>.<DOMAIN_BASE>`, например `demo.home.test`. Берите суффикс, который не пересекается с реальным DNS и multicast DNS: `.test` или собственный поддомен. Избегайте `.local` (зарезервирован под mDNS; на macOS разрешение имён может подвисать на секунды).

## 2. Манифест

`test-app.yaml` на сервере:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <PROJECT_NAME>-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <PROJECT_NAME>-web
  template:
    metadata:
      labels:
        app: <PROJECT_NAME>-web
    spec:
      containers:
      - name: web
        image: nginx:stable
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: <PROJECT_NAME>-web
spec:
  selector:
    app: <PROJECT_NAME>-web
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <PROJECT_NAME>-web
spec:
  rules:
  - host: <PROJECT_NAME>.<DOMAIN_BASE>
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: <PROJECT_NAME>-web
            port:
              number: 80
```

Перед применением замените плейсхолдеры реальными значениями (`sed` или редактор). Отступы в YAML только пробелами; значения `selector`/`labels` в Deployment и Service должны совпадать.

```bash
kubectl apply -f test-app.yaml
kubectl get pods,svc,ingress
```

## 3. Запись в hosts на ноутбуке

Ноутбук должен резолвить имя в адрес сервера. Добавьте одну строку в файл hosts (нужен `sudo`):

Файл: `/etc/hosts` (`sudo nano /etc/hosts`)

```
<SERVER_IP> <PROJECT_NAME>.<DOMAIN_BASE>
```

Один IP, затем одно или несколько имён через пробел; не повторяйте одно имя в нескольких строках. Для каждого нового проекта дописывайте его имя в эту строку. На macOS, если новая запись не применилась: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.

## Проверка

```bash
ping -c1 <PROJECT_NAME>.<DOMAIN_BASE>        # показывает <SERVER_IP>
curl -I http://<PROJECT_NAME>.<DOMAIN_BASE>  # HTTP/1.1 200 OK
```

Браузер: `http://<PROJECT_NAME>.<DOMAIN_BASE>` показывает "Welcome to nginx!". Без правки hosts:

```bash
curl -H "Host: <PROJECT_NAME>.<DOMAIN_BASE>" http://<SERVER_IP>/
```

| Симптом | Причина / решение |
|---|---|
| `404 page not found` (страница Traefik) | `host` в Ingress отличается от введённого имени или Ingress нет: `kubectl get ingress` |
| Имя не резолвится | Нет записи в hosts или опечатка; `ping` должен показывать `<SERVER_IP>` |
| `ContainerCreating` минутами / `ImagePullBackOff` | Сервер не может скачать образ; `kubectl describe pod <pod>`, проверьте интернет/DNS |
| `Pending` | Не хватает CPU/RAM; смотрите `Events` в `kubectl describe pod` |
| `error validating` при apply | Неверные отступы или табы в YAML |
| `502`/`Bad Gateway` | Селектор Service не совпадает с labels Pod или неверный `targetPort`; `kubectl get endpoints` должен показывать IP Pod |

## Очистка

```bash
kubectl delete -f test-app.yaml
```

Удалите строку из hosts, если имя больше не понадобится.

Next: [Продуктивность в шелле: Starship](shell-productivity-starship.md)
