# Довідник: маніфест застосунку (`app.yaml`)

Покрокові нотатки до кожного поля [`examples/wordpress/app.yaml`](../../../examples/wordpress/app.yaml): один под з PHP-FPM і Nginx, Service та Traefik Ingress. Користуйтеся ним, адаптуючи файл під новий проєкт.

Основні об'єкти: **Deployment** підтримує N однакових подів; **Service** надає їм стабільне DNS-ім'я всередині кластера; **Ingress** зіставляє зовнішнє ім'я хоста із Service (обслуговується Traefik). Об'єкти в одному файлі розділяються `---`.

## Deployment

| Поле | Що робить | Коли змінювати |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-app` | Назва Deployment; ціль `rollout restart` | Завжди задавайте для кожного проєкту |
| `metadata.namespace` | Namespace, у якому живе об'єкт | Завжди = namespace проєкту |
| `spec.replicas: 1` | Кількість подів. Лишайте 1: код і дані лежать на диску одного вузла | Ніколи на одновузловому homelab |
| `spec.selector.matchLabels` | Якими подами володіє цей Deployment | Має точно дорівнювати `template.metadata.labels`, інакше `apply` завершується помилкою `selector does not match template labels` |
| `template.metadata.labels: app: <PROJECT_NAME>` | Мітка на подах; за нею обирає Service | Має збігатися із `selector` Service |
| `containers[php].image` | Образ PHP-FPM, зібраний із Dockerfile проєкту | Нова назва/тег образу |
| `imagePullPolicy: Never` | Ніколи не завантажувати з реєстру; використовувати локальний образ containerd | Приберіть, якщо образ береться з реєстру |
| `workingDir: /var/www/html` | Робочий каталог процесу PHP за замовчуванням | Рідко |
| `ports.containerPort: 9000` | Лише документація (порт FPM); нічого не відкриває | Рідко |
| `containers[nginx].image: nginx:alpine` | Стандартний Nginx | Зафіксуйте версію для відтворюваності |
| `ports.containerPort: 80` | Лише документація | Якщо Nginx слухає інший порт |
| `volumeMounts[code-volume]` | Каталог проєкту змонтовано в обох контейнерах у `/var/www/html`; у Nginx лише для читання | Шлях монтування має збігатися з Dockerfile і `root` у `default.conf` |
| `volumeMounts[nginx-conf]` → `/etc/nginx/conf.d` | Монтує каталог конфігурації сайту лише для читання | Лише якщо ви переносите конфіг |

Обидва контейнери ділять один мережевий простір імен, тому Nginx звертається до PHP-FPM за адресою `127.0.0.1:9000`.

## Томи (`hostPath`)

`hostPath` відображає каталог на диску вузла в контейнер. Це найпростіший тип тому, який прив'язує под до цього сервера, що прийнятно для одного вузла.

| Том | `path` | `type` |
|---|---|---|
| `code-volume` | `/home/<SERVER_USER>/workspace/<PROJECT_GROUP>/<PROJECT_NAME>` | `DirectoryOrCreate` |
| `nginx-conf` | `.../<PROJECT_NAME>/k8s-local/nginx` | `Directory` |

- `Directory`: шлях має вже існувати, інакше под залишається в `Pending` (`hostPath type check failed` у `kubectl describe pod`). Використовуйте для того, що обов'язково має бути на місці.
- `DirectoryOrCreate`: Kubernetes створює порожній каталог, якщо його немає. Зручно, але помилка в назві непомітно дасть вам порожній корінь сайту.
- Монтуйте лише один каталог конфігурації, а не все дерево конфігурації Nginx із репозиторію.
- TLS завершується на Traefik, тому сертифікати в Nginx не монтуються.

## Service

| Поле | Що робить | Коли змінювати |
|---|---|---|
| `metadata.name: <PROJECT_NAME>-service` | DNS-ім'я всередині кластера `<PROJECT_NAME>-service.<PROJECT_NAME>.svc.cluster.local` | Для кожного проєкту; у Ingress на нього треба посилатися так само |
| `spec.selector: app: <PROJECT_NAME>` | Поди, що отримують трафік | Має збігатися з мітками подів, інакше Service не має endpoints |
| `ports.port: 80` | Порт, який слухає Service | Якщо інші поди звертаються на інший порт |
| `ports.targetPort: 80` | Порт контейнера, куди пересилається трафік (Nginx) | Якщо Nginx слухає інший порт |

Тип за замовчуванням `ClusterIP`: доступний лише всередині кластера; зовнішній трафік входить через Ingress.

## Ingress

| Поле | Що робить | Коли змінювати |
|---|---|---|
| `traefik.../router.entrypoints: web,websecure` | Обслуговувати на точках входу Traefik HTTP (80) і HTTPS (443) | Залиште лише `websecure`, щоб відхиляти звичайний HTTP |
| `traefik.../router.tls: "true"` | Вмикає TLS на роутері; використовується самопідписаний сертифікат Traefik за замовчуванням (попередження браузера) | Додайте блок `tls:`/cert resolver для справжнього сертифіката |
| `rules[0].host: <PROJECT_NAME>.<DOMAIN_BASE>` | Ім'я хоста, що маршрутизується на цей проєкт; два Ingress з однаковим хостом конфліктують | Завжди унікальне для кожного проєкту |
| `paths: / (Prefix)` | Усе, що починається з `/` | Лише щоб опублікувати підшлях |
| `backend.service.name/port` | Цільовий Service і його порт | Має дорівнювати назві Service і `port` вище |

## Перевірка

```bash
kubectl apply --dry-run=server -f app.yaml
kubectl -n <PROJECT_NAME> get endpoints <PROJECT_NAME>-service     # має містити IP пода
kubectl -n <PROJECT_NAME> describe ingress <PROJECT_NAME>-ingress
```

Порожній `ENDPOINTS` означає, що селектор і мітки подів відрізняються.

Далі: [Маніфест бази даних](database-manifest.md)
