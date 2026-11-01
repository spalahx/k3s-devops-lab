# GitLab CI pipeline: сборка и деплой в K3s

> **Статус: не проверено на реальном железе.** На эталонном сервере, с которым сверялось это руководство, не установлен GitLab Runner, поэтому конвейер на этой странице не проходился от начала до конца. Считайте команды отправной точкой и проверяйте каждую.

Настраивает self-hosted GitLab Runner на сервере и `.gitlab-ci.yml`, который собирает Docker-образ, пушит его в GitLab Container Registry и обновляет существующий Deployment в K3s при каждом push в `main`. Сначала используйте тестовый проект. Собственный runner не нужен, если хватает shared runners на gitlab.com и кластер доступен им (в домашней сети обычно недоступен).

Предусловия: работающий [K3s](../03-containers-and-k3s/k3s-install.md) с Deployment приложения, один раз созданным вручную (см. [пошаговый деплой](../05-deploying-projects/generic-deployment-walkthrough.md)), и [Docker](../03-containers-and-k3s/docker-install.md) на сервере. Пайплайн только обновляет образ, манифесты он не создаёт.

Используемые имена: namespace `<PROJECT_NAME>`, Deployment `<PROJECT_NAME>-app`, контейнер `app`.

## 1. Установить GitLab Runner

```bash
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
sudo apt-get install -y gitlab-runner
gitlab-runner --version
```

Скрипт добавляет официальный apt-репозиторий; если не хотите передавать его в `bash`, сначала прочитайте.

## 2. Зарегистрировать runner

В GitLab: проект -> **Settings -> CI/CD -> Runners -> New project runner**. Укажите тег (например, `k3s`), создайте runner и скопируйте authentication token (`glrt-...`). Registration tokens устарели, используйте этот способ.

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

Для self-hosted GitLab укажите свой URL. `--docker-privileged` нужен для сервиса `docker:dind`, собирающего образы; при этом каждая задача получает повышенные права на хосте, поэтому запускайте на этом runner только доверенные проекты.

```bash
sudo gitlab-runner verify
sudo systemctl status gitlab-runner
```

В **Settings -> CI/CD -> Runners** у runner должна гореть зелёная точка.

## 3. Создать ограниченную учётку деплоя в K3s

Не отдавайте CI админский kubeconfig. Создайте ServiceAccount, которому разрешено обновлять Deployments в одном namespace:

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

Соберите kubeconfig из токена. Адрес сервера должен быть доступен из контейнера задачи, поэтому используйте `<SERVER_IP>`, а не `127.0.0.1`:

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

Если при включённом UFW контейнер не достаёт `<SERVER_IP>:6443`, разрешите диапазон Docker bridge: `sudo ufw allow from 172.16.0.0/12 to any port 6443 proto tcp`. Если сертификат отклоняется для выбранного адреса, добавьте `tls-san: [<SERVER_IP>]` в `/etc/rancher/k3s/config.yaml` и перезапустите K3s.

## 4. Доступ кластера к registry

K3s должен скачать образ, который запушила задача. Создайте deploy token в GitLab (**Settings -> Repository -> Deploy tokens**, scope `read_registry`), затем:

```bash
kubectl -n <PROJECT_NAME> create secret docker-registry gitlab-registry \
  --docker-server=registry.gitlab.com \
  --docker-username=<DEPLOY_TOKEN_USER> \
  --docker-password=<DEPLOY_TOKEN_VALUE>
kubectl -n <PROJECT_NAME> patch deployment <PROJECT_NAME>-app --type merge \
  -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"gitlab-registry"}]}}}}'
```

`<DEPLOY_TOKEN_USER>` и `<DEPLOY_TOKEN_VALUE>` — имя пользователя и токен, которые GitLab показывает один раз при создании. (Задача может собрать образ, но не может положить его в containerd внутри K3s; передача tar между задачами, как часто показывают, не делает образ доступным кластеру. Используйте registry.)

## 5. CI/CD-переменные

**Settings -> CI/CD -> Variables -> Add variable**:

| Key | Type | Value | Флаги |
|---|---|---|---|
| `KUBECONFIG` | File | содержимое `ci-kubeconfig` | Protected |

GitLab записывает File-переменную во временный файл и подставляет в `$KUBECONFIG` путь к нему, `kubectl` читает его автоматически. `Masked` недоступен для многострочных значений; Protected ограничивает переменную защищёнными ветками (убедитесь, что `main` protected). После этого удалите `ci-kubeconfig` с сервера.

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

| Элемент | Пояснение |
|---|---|
| `$CI_COMMIT_SHORT_SHA` | Предопределённая переменная GitLab; уникальный тег на коммит, по нему видно, какая версия запущена |
| `docker:27-dind` | Сервис Docker-in-Docker, чтобы задача могла выполнять `docker build` |
| `DOCKER_TLS_CERTDIR` | Клиент и демон dind используют общие TLS-сертификаты; без этого `Cannot connect to the Docker daemon` |
| `$CI_REGISTRY_*` | Предопределены; job token автоматически входит в registry проекта |
| `alpine/k8s:<KUBECTL_VERSION>` | Образ с `kubectl` и оболочкой. `kubectl` может отличаться от кластера не более чем на одну минорную версию, поэтому берите тег по кластеру: `kubectl version` показывает версию сервера (например, `v1.36.4` означает тег `1.36.x`). Закрепляйте точный тег, не `latest` |
| Namespace | Берётся из контекста kubeconfig, `-n` не нужен |

## Verify

Сделайте push в `main`, проверьте **CI/CD -> Pipelines** (оба этапа зелёные) и кластер:

```bash
kubectl -n <PROJECT_NAME> rollout history deployment/<PROJECT_NAME>-app
kubectl -n <PROJECT_NAME> get deploy <PROJECT_NAME>-app -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Тег образа должен совпадать с short SHA последнего коммита.

## Gotchas

| Симптом | Причина / решение |
|---|---|
| Runner offline | `sudo systemctl restart gitlab-runner`; проверьте доступ к URL GitLab |
| `Cannot connect to the Docker daemon at tcp://docker:2375` | Runner зарегистрирован без `--docker-privileged` или не совпадает `DOCKER_TLS_CERTDIR` |
| `ImagePullBackOff` после деплоя | Нет/неверный секрет `gitlab-registry` или `imagePullSecrets`; ошибку покажет `kubectl describe pod` |
| `Unable to connect to the server` / `x509` | Контейнер задачи не достаёт `<SERVER_IP>:6443` (UFW) или в сертификате нет этого IP (`tls-san`) |
| `forbidden: ... cannot patch resource` | В Role не хватает verb или Deployment в другом namespace |
| Переменная пустая в задаче | Protected-переменная на незащищённой ветке |
| Деплой прошёл, но видна старая страница | Кэш браузера; `rollout status` подтверждает новый pod |

Next: [Основы Helm](../08-monitoring/helm-basics.md)
