# GitLab CI Pipeline: Build and Deploy to K3s

Sets up a self-hosted GitLab Runner on the server and a `.gitlab-ci.yml` that builds a Docker image, pushes it to the GitLab Container Registry, and rolls it out to an existing K3s Deployment on every push to `main`. Use a throwaway project first. Skip the self-hosted runner if the shared runners of gitlab.com are sufficient and the cluster is reachable from them (it usually is not, on a home network).

Prerequisites: a working [K3s](../03-containers-and-k3s/k3s-install.md) with the app Deployment already created once by hand (see [deployment walkthrough](../05-deploying-projects/generic-deployment-walkthrough.md)), and [Docker](../03-containers-and-k3s/docker-install.md) on the server. The pipeline only updates the image; it does not create manifests.

Variables used: namespace `<PROJECT_NAME>`, Deployment `<PROJECT_NAME>-app`, container `app`.

## 1. Install GitLab Runner

```bash
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
sudo apt-get install -y gitlab-runner
gitlab-runner --version
```

The script adds the official apt repository; review it first if you prefer not to pipe to `bash`.

## 2. Register the runner

In GitLab: project -> **Settings -> CI/CD -> Runners -> New project runner**. Tick a tag (e.g. `k3s`), create it, and copy the authentication token (`glrt-...`). Registration tokens are deprecated; use this flow.

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

Use your own GitLab URL for a self-hosted instance. `--docker-privileged` is required for the `docker:dind` service used to build images; every job then runs with elevated rights on the host, so only run trusted projects on this runner.

```bash
sudo gitlab-runner verify
sudo systemctl status gitlab-runner
```

The runner should show a green dot in **Settings -> CI/CD -> Runners**.

## 3. Create a restricted deploy identity in K3s

Do not hand the admin kubeconfig to CI. Create a ServiceAccount allowed to update Deployments in one namespace:

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

Build a kubeconfig from the token. The server address must be reachable from inside the job container, so use `<SERVER_IP>`, not `127.0.0.1`:

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

If the container cannot reach `<SERVER_IP>:6443` while UFW is on, allow the Docker bridge range: `sudo ufw allow from 172.16.0.0/12 to any port 6443 proto tcp`. If the certificate is rejected for the chosen address, add `tls-san: [<SERVER_IP>]` to `/etc/rancher/k3s/config.yaml` and restart K3s.

## 4. Registry pull access in the cluster

K3s must pull the image the job pushes. Create a deploy token in GitLab (**Settings -> Repository -> Deploy tokens**, scope `read_registry`), then:

```bash
kubectl -n <PROJECT_NAME> create secret docker-registry gitlab-registry \
  --docker-server=registry.gitlab.com \
  --docker-username=<DEPLOY_TOKEN_USER> \
  --docker-password=<DEPLOY_TOKEN_VALUE>
kubectl -n <PROJECT_NAME> patch deployment <PROJECT_NAME>-app --type merge \
  -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"gitlab-registry"}]}}}}'
```

`<DEPLOY_TOKEN_USER>` and `<DEPLOY_TOKEN_VALUE>` are the username and token GitLab shows once at creation. (The job can build an image, but it cannot reach containerd inside K3s; passing a tar between jobs, as is often shown, does not make the image available to the cluster. Use a registry.)

## 5. CI/CD variables

**Settings -> CI/CD -> Variables -> Add variable**:

| Key | Type | Value | Flags |
|---|---|---|---|
| `KUBECONFIG` | File | contents of `ci-kubeconfig` | Protected |

GitLab writes a File variable to a temp path and sets `$KUBECONFIG` to it, which `kubectl` reads automatically. `Masked` is not available for multi-line values; Protected limits it to protected branches (make sure `main` is protected). Delete `ci-kubeconfig` from the server afterwards.

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
    name: alpine/k8s:1.30.4
    entrypoint: [""]
  tags: [k3s]
  script:
    - kubectl set image deployment/<PROJECT_NAME>-app app="$IMAGE"
    - kubectl rollout status deployment/<PROJECT_NAME>-app --timeout=180s
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

| Item | Explanation |
|---|---|
| `$CI_COMMIT_SHORT_SHA` | Predefined by GitLab; a unique tag per commit, so the running version is traceable |
| `docker:27-dind` | Docker-in-Docker service so the job can run `docker build` |
| `DOCKER_TLS_CERTDIR` | Makes the client and the dind daemon share TLS certificates; omitting it gives `Cannot connect to the Docker daemon` |
| `$CI_REGISTRY_*` | Predefined; the job token logs in to the project's registry automatically |
| `alpine/k8s` | Image with `kubectl` and a shell; pin the tag to match the cluster version |
| Namespace | Taken from the kubeconfig context, so no `-n` is needed |

## Verify

Push to `main`, then check **CI/CD -> Pipelines** (both stages green) and the cluster:

```bash
kubectl -n <PROJECT_NAME> rollout history deployment/<PROJECT_NAME>-app
kubectl -n <PROJECT_NAME> get deploy <PROJECT_NAME>-app -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

The image tag must equal the short SHA of the last commit.

## Gotchas

| Symptom | Cause / fix |
|---|---|
| Runner offline | `sudo systemctl restart gitlab-runner`; check network access to the GitLab URL |
| `Cannot connect to the Docker daemon at tcp://docker:2375` | Runner not registered with `--docker-privileged`, or `DOCKER_TLS_CERTDIR` mismatch |
| `ImagePullBackOff` after deploy | Missing/wrong `gitlab-registry` secret or `imagePullSecrets`; `kubectl describe pod` shows the pull error |
| `Unable to connect to the server` / `x509` | Job container cannot reach `<SERVER_IP>:6443` (UFW) or the certificate lacks that IP (`tls-san`) |
| `forbidden: ... cannot patch resource` | Role lacks a verb or the Deployment is in another namespace |
| Variable empty in the job | `Protected` variable on an unprotected branch |
| Deploy succeeded, old page shown | Browser cache; `rollout status` confirms the new pod |

Next: [Helm basics](../08-monitoring/helm-basics.md)
