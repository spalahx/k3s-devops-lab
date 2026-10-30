# Ingress з Traefik і перший застосунок

Розгортає тимчасовий застосунок Nginx і відкриває його як `http://<PROJECT_NAME>.<DOMAIN_BASE>` через ingress-контролер Traefik, який K3s встановлює за замовчуванням. Виконайте це один раз, щоб підтвердити роботу всього ланцюга (Deployment, Service, Ingress, DNS на ноутбуці) перед розгортанням справжніх проєктів.

## Як це працює

```
browser --> <SERVER_IP>:80 --> Traefik (kube-system) --> Ingress rule (Host header) --> Service --> Pod
```

| Об'єкт | Роль |
|---|---|
| Deployment | Підтримує запущеними N реплік пода |
| Service | Стабільна внутрішня адреса для подів, вибраних за селектором міток |
| Ingress | Правило «запити для хоста X йдуть до Service Y»; Traefik підхоплює його автоматично |

- K3s прив'язує Traefik до портів 80/443 вузла (сервіс `traefik`, тип `LoadBalancer`, обслуговується вбудованим ServiceLB), тож усі проєкти мають одну IP-адресу й порт; маршрутизація йде за заголовком `Host`.
- K3s позначає Traefik як типовий ingress-клас, тому `ingressClassName` можна не вказувати.
- Сам Traefik налаштовувати не потрібно.

## 1. Виберіть ім'я хоста

`<PROJECT_NAME>.<DOMAIN_BASE>`, наприклад `demo.home.test`. Використовуйте суфікс, який не може конфліктувати зі справжнім DNS або multicast DNS: `.test` або піддомен, яким ви володієте. Уникайте `.local` (зарезервовано для mDNS; на macOS пошук імен може зависати на кілька секунд).

## 2. Маніфест

`test-app.yaml` на сервері:

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

Перед застосуванням замініть плейсхолдери на справжні значення (`sed` або редактор). Відступи в YAML — лише пробіли; значення `selector`/`labels` мають збігатися в Deployment і Service.

```bash
kubectl apply -f test-app.yaml
kubectl get pods,svc,ingress
```

## 3. Запис у hosts на ноутбуці

Ноутбук має зіставляти це ім'я з сервером. Додайте один рядок у файл hosts (потрібен `sudo`):

Файл: `/etc/hosts` (`sudo nano /etc/hosts`)

```
<SERVER_IP> <PROJECT_NAME>.<DOMAIN_BASE>
```

Одна IP-адреса, далі одне або кілька імен через пробіл; не повторюйте те саме ім'я в кількох рядках. Кожен новий проєкт додає своє ім'я в цей рядок. На macOS, якщо новий запис ігнорується: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.

## Перевірка

```bash
ping -c1 <PROJECT_NAME>.<DOMAIN_BASE>        # shows <SERVER_IP>
curl -I http://<PROJECT_NAME>.<DOMAIN_BASE>  # HTTP/1.1 200 OK
```

Браузер: `http://<PROJECT_NAME>.<DOMAIN_BASE>` показує "Welcome to nginx!". Без редагування hosts:

```bash
curl -H "Host: <PROJECT_NAME>.<DOMAIN_BASE>" http://<SERVER_IP>/
```

| Симптом | Причина / рішення |
|---|---|
| `404 page not found` (сторінка Traefik) | `host` в Ingress відрізняється від введеного імені, або Ingress не існує: `kubectl get ingress` |
| Ім'я не розв'язується | Запису в hosts немає або помилка в написанні; `ping` має показати `<SERVER_IP>` |
| `ContainerCreating` кілька хвилин / `ImagePullBackOff` | Сервер не може завантажити образ; `kubectl describe pod <pod>` і перевірте інтернет/DNS |
| `Pending` | Недостатньо CPU/RAM; див. `Events` у `kubectl describe pod` |
| `error validating` під час apply | Відступи або табуляції в YAML |
| `502`/`Bad Gateway` | Селектор Service не збігається з мітками пода, або хибний `targetPort`; `kubectl get endpoints` має показувати IP пода |

## Очищення

```bash
kubectl delete -f test-app.yaml
```

Видаліть рядок із hosts, якщо ім'я більше не знадобиться.

Далі: [Продуктивність оболонки зі Starship](shell-productivity-starship.md)
