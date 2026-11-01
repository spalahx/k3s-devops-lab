# Конвеєр GitLab CI: збірка та розгортання в K3s

> **Статус: не перевірено на реальному обладнанні.** На еталонному сервері, з яким звірялася ця інструкція, не встановлено GitLab Runner, тому конвеєр на цій сторінці не проходився від початку до кінця. Сприймайте команди як відправну точку і перевіряйте кожну.

Налаштовує self-hosted GitLab Runner на сервері та `.gitlab-ci.yml`, який збирає образ Docker, надсилає його в GitLab Container Registry і викочує в наявний Deployment K3s після кожного push у `main`. Спершу скористайтеся тестовим проєктом. Пропустіть self-hosted runner, якщо спільних runner'ів gitlab.com достатньо і кластер для них доступний (у домашній мережі зазвичай ні).

Передумови: робочий [K3s](../03-containers-and-k3s/k3s-install.md) із Deployment застосунку, один раз створеним вручну (див. [покрокове розгортання](../05-deploying-projects/generic-deployment-walkthrough.md)), та [Docker](../03-containers-and-k3s/docker-install.md) на сервері. Конвеєр лише оновлює образ; маніфести він не створює.

Використовувані змінні: namespace `<PROJECT_NAME>`, Deployment `<PROJECT_NAME>-app`, контейнер `app`.

## 1. Встановлення GitLab Runner

```bash
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
sudo apt-get install -y gitlab-runner
gitlab-runner --version
```

Скрипт додає офіційний apt-репозиторій; якщо не хочете передавати його в `bash` через конвеєр, спершу перегляньте його.

## 2. Реєстрація runner'а

У GitLab: проєкт -> **Settings -> CI/CD -> Runners -> New project runner**. Позначте тег (наприклад, `k3s`), створіть runner і скопіюйте токен автентифікації (`glrt-...`). Реєстраційні токени застарілі; використовуйте цей спосіб.

```bash
sudo gitlab-runner register \
  --non-interactive \
  --url https://gitlab.com/ \
  --token glrt-XXXXXXXX \
  --executor docker \
  --docker-image alpine:3.20 \
  --docker-privileged \
  --description "home-k3s-runner"
```

Для self-hosted екземпляра вкажіть власну URL-адресу GitLab. `--docker-privileged` потрібен для сервісу `docker:dind`, який використовується для збірки образів; тоді кожне завдання виконується на хості з підвищеними правами, тож запускайте на цьому runner'і лише довірені проєкти.

```bash
sudo gitlab-runner verify
sudo systemctl status gitlab-runner
```

Runner має відображатися із зеленою позначкою в **Settings -> CI/CD -> Runners**.

## 3. Створення обмеженої identity для розгортання в K3s

Не передавайте адміністративний kubeconfig у CI. Створіть ServiceAccount, якому дозволено оновлювати Deployment'и в одному namespace:

```bash
kubectl -n <PROJECT_NAME> create serviceaccount ci-deployer
kubectl -n <PROJECT_NAME> apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ci-deployer
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "patch", "update"]
  - apiGroups: ["apps"]
    resources: ["replicasets"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-deployer
subjects:
  - kind: ServiceAccount
    name: ci-deployer
roleRef:
  kind: Role
  name: ci-deployer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Secret
metadata:
  name: ci-deployer-token
  annotations:
    kubernetes.io/service-account.name: ci-deployer
type: kubernetes.io/service-account-token
EOF
```

Побудуйте kubeconfig з токена. Адреса сервера має бути доступна зсередини контейнера завдання, тому використовуйте `<SERVER_IP>`, а не `127.0.0.1`:

```bash
NS=<PROJECT_NAME>
TOKEN=$(kubectl -n $NS get secret ci-deployer-token -o jsonpath='{.data.token}' | base64 -d)
CA=$(kubectl -n $NS get secret ci-deployer-token -o jsonpath='{.data.ca\.crt}')
cat > ci-kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- name: k3s
  cluster:
    server: https://<SERVER_IP>:6443
    certificate-authority-data: $CA
users:
- name: ci-deployer
  user:
    token: $TOKEN
contexts:
- name: ci
  context: {cluster: k3s, user: ci-deployer, namespace: $NS}
current-context: ci
EOF
KUBECONFIG=./ci-kubeconfig kubectl get deploy
```

Якщо контейнер не може дістатися до `<SERVER_IP>:6443` при ввімкненому UFW, дозвольте діапазон мосту Docker: `sudo ufw allow from 172.16.0.0/12 to any port 6443 proto tcp`. Якщо сертифікат відхиляється для обраної адреси, додайте `tls-san: [<SERVER_IP>]` до `/etc/rancher/k3s/config.yaml` і перезапустіть K3s.

## 4. Доступ кластера до registry для завантаження образів

K3s має завантажувати образ, який надсилає завдання. Створіть deploy token у GitLab (**Settings -> Repository -> Deploy tokens**, scope `read_registry`), потім:

```bash
kubectl -n <PROJECT_NAME> create secret docker-registry gitlab-registry \
  --docker-server=registry.gitlab.com \
  --docker-username=<DEPLOY_TOKEN_USER> \
  --docker-password=<DEPLOY_TOKEN_VALUE>
kubectl -n <PROJECT_NAME> patch deployment <PROJECT_NAME>-app --type merge \
  -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"gitlab-registry"}]}}}}'
```

`<DEPLOY_TOKEN_USER>` і `<DEPLOY_TOKEN_VALUE>` — це ім'я користувача й токен, які GitLab показує один раз під час створення. (Завдання може зібрати образ, але не має доступу до containerd усередині K3s; передавання tar-архіву між завданнями, як часто показують, не робить образ доступним для кластера. Використовуйте registry.)

## 5. Змінні CI/CD

**Settings -> CI/CD -> Variables -> Add variable**:

| Ключ | Тип | Значення | Прапорці |
|---|---|---|---|
| `KUBECONFIG` | File | вміст `ci-kubeconfig` | Protected |

GitLab записує змінну типу File у тимчасовий шлях і встановлює `$KUBECONFIG` на нього, що `kubectl` читає автоматично. `Masked` недоступний для багаторядкових значень; Protected обмежує змінну захищеними гілками (переконайтеся, що `main` захищена). Після цього видаліть `ci-kubeconfig` із сервера.

## 6. `.gitlab-ci.yml`

```yaml
stages:
  - build
  - deploy

variables:
  IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

build:
  stage: build
  image: docker:27
  services:
    - docker:27-dind
  variables:
    DOCKER_TLS_CERTDIR: "/certs"
  tags: [k3s]
  script:
    - echo "$CI_REGISTRY_PASSWORD" | docker login -u "$CI_REGISTRY_USER" --password-stdin "$CI_REGISTRY"
    - docker build -t "$IMAGE" -t "$CI_REGISTRY_IMAGE:latest" .
    - docker push "$IMAGE"
    - docker push "$CI_REGISTRY_IMAGE:latest"
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

deploy:
  stage: deploy
  image:
    name: alpine/k8s:<KUBECTL_VERSION>
    entrypoint: [""]
  tags: [k3s]
  script:
    - kubectl set image deployment/<PROJECT_NAME>-app app="$IMAGE"
    - kubectl rollout status deployment/<PROJECT_NAME>-app --timeout=180s
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

| Елемент | Пояснення |
|---|---|
| `$CI_COMMIT_SHORT_SHA` | Попередньо визначена змінна GitLab; унікальний тег для кожного коміту, тож запущену версію можна відстежити |
| `docker:27-dind` | Сервіс Docker-in-Docker, щоб завдання могло виконувати `docker build` |
| `DOCKER_TLS_CERTDIR` | Змушує клієнт і демон dind використовувати спільні TLS-сертифікати; без нього виникає `Cannot connect to the Docker daemon` |
| `$CI_REGISTRY_*` | Попередньо визначені; токен завдання автоматично авторизується в registry проєкту |
| `alpine/k8s:<KUBECTL_VERSION>` | Образ із `kubectl` і оболонкою. `kubectl` може відрізнятися від кластера не більше ніж на одну мінорну версію, тому беріть тег за кластером: `kubectl version` показує версію сервера (наприклад, `v1.36.4` означає тег `1.36.x`). Закріплюйте точний тег, не `latest` |
| Namespace | Береться з контексту kubeconfig, тому `-n` не потрібен |

## Перевірка

Зробіть push у `main`, потім перевірте **CI/CD -> Pipelines** (обидва етапи зелені) і кластер:

```bash
kubectl -n <PROJECT_NAME> rollout history deployment/<PROJECT_NAME>-app
kubectl -n <PROJECT_NAME> get deploy <PROJECT_NAME>-app -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Тег образу має дорівнювати короткому SHA останнього коміту.

## Типові проблеми

| Симптом | Причина / виправлення |
|---|---|
| Runner офлайн | `sudo systemctl restart gitlab-runner`; перевірте мережевий доступ до URL GitLab |
| `Cannot connect to the Docker daemon at tcp://docker:2375` | Runner зареєстровано без `--docker-privileged` або `DOCKER_TLS_CERTDIR` не збігається |
| `ImagePullBackOff` після розгортання | Відсутній/неправильний secret `gitlab-registry` або `imagePullSecrets`; `kubectl describe pod` показує помилку завантаження |
| `Unable to connect to the server` / `x509` | Контейнер завдання не бачить `<SERVER_IP>:6443` (UFW) або в сертифікаті немає цієї IP-адреси (`tls-san`) |
| `forbidden: ... cannot patch resource` | У Role бракує дієслова або Deployment в іншому namespace |
| Змінна порожня в завданні | Змінна `Protected` на незахищеній гілці |
| Розгортання успішне, але показується стара сторінка | Кеш браузера; `rollout status` підтверджує новий pod |

Далі: [Основи Helm](../08-monitoring/helm-basics.md)
