# Pipeline GitLab CI : build et déploiement sur K3s

Met en place un GitLab Runner auto-hébergé sur le serveur et un `.gitlab-ci.yml` qui construit une image Docker, la pousse vers le GitLab Container Registry et la déploie sur un Deployment K3s existant à chaque push sur `main`. Utilisez d'abord un projet jetable. Ignorez le runner auto-hébergé si les runners partagés de gitlab.com suffisent et que le cluster leur est accessible (ce n'est généralement pas le cas sur un réseau domestique).

Prérequis : un [K3s](../03-containers-and-k3s/k3s-install.md) fonctionnel avec le Deployment de l'application déjà créé une fois à la main (voir le [guide de déploiement](../05-deploying-projects/generic-deployment-walkthrough.md)), et [Docker](../03-containers-and-k3s/docker-install.md) sur le serveur. Le pipeline ne fait que mettre à jour l'image ; il ne crée pas de manifestes.

Variables utilisées : namespace `<PROJECT_NAME>`, Deployment `<PROJECT_NAME>-app`, conteneur `app`.

## 1. Installer GitLab Runner

```bash
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
sudo apt-get install -y gitlab-runner
gitlab-runner --version
```

Le script ajoute le dépôt apt officiel ; relisez-le d'abord si vous préférez ne pas l'envoyer directement à `bash`.

## 2. Enregistrer le runner

Dans GitLab : projet -> **Settings -> CI/CD -> Runners -> New project runner**. Cochez un tag (par ex. `k3s`), créez-le et copiez le jeton d'authentification (`glrt-...`). Les jetons d'enregistrement sont obsolètes ; utilisez ce processus.

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

Utilisez votre propre URL GitLab pour une instance auto-hébergée. `--docker-privileged` est requis pour le service `docker:dind` utilisé pour construire les images ; chaque job s'exécute alors avec des droits élevés sur l'hôte, n'exécutez donc que des projets de confiance sur ce runner.

```bash
sudo gitlab-runner verify
sudo systemctl status gitlab-runner
```

Le runner doit afficher un point vert dans **Settings -> CI/CD -> Runners**.

## 3. Créer une identité de déploiement restreinte dans K3s

Ne donnez pas le kubeconfig administrateur à la CI. Créez un ServiceAccount autorisé à mettre à jour les Deployments dans un seul namespace :

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

Construisez un kubeconfig à partir du jeton. L'adresse du serveur doit être accessible depuis le conteneur du job, utilisez donc `<SERVER_IP>` et non `127.0.0.1` :

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

Si le conteneur ne peut pas atteindre `<SERVER_IP>:6443` alors qu'UFW est actif, autorisez la plage du pont Docker : `sudo ufw allow from 172.16.0.0/12 to any port 6443 proto tcp`. Si le certificat est rejeté pour l'adresse choisie, ajoutez `tls-san: [<SERVER_IP>]` à `/etc/rancher/k3s/config.yaml` et redémarrez K3s.

## 4. Accès au registre depuis le cluster

K3s doit pouvoir tirer l'image poussée par le job. Créez un deploy token dans GitLab (**Settings -> Repository -> Deploy tokens**, portée `read_registry`), puis :

```bash
kubectl -n <PROJECT_NAME> create secret docker-registry gitlab-registry \
  --docker-server=registry.gitlab.com \
  --docker-username=<DEPLOY_TOKEN_USER> \
  --docker-password=<DEPLOY_TOKEN_VALUE>
kubectl -n <PROJECT_NAME> patch deployment <PROJECT_NAME>-app --type merge \
  -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"gitlab-registry"}]}}}}'
```

`<DEPLOY_TOKEN_USER>` et `<DEPLOY_TOKEN_VALUE>` sont le nom d'utilisateur et le jeton que GitLab affiche une seule fois à la création. (Le job peut construire une image, mais il ne peut pas atteindre containerd à l'intérieur de K3s ; transmettre une archive tar entre jobs, comme on le voit souvent, ne rend pas l'image disponible pour le cluster. Utilisez un registre.)

## 5. Variables CI/CD

**Settings -> CI/CD -> Variables -> Add variable** :

| Clé | Type | Valeur | Options |
|---|---|---|---|
| `KUBECONFIG` | File | contenu de `ci-kubeconfig` | Protected |

GitLab écrit une variable de type File dans un chemin temporaire et définit `$KUBECONFIG` sur celui-ci, ce que `kubectl` lit automatiquement. `Masked` n'est pas disponible pour les valeurs multilignes ; Protected la limite aux branches protégées (assurez-vous que `main` est protégée). Supprimez ensuite `ci-kubeconfig` du serveur.

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

| Élément | Explication |
|---|---|
| `$CI_COMMIT_SHORT_SHA` | Prédéfini par GitLab ; un tag unique par commit, ce qui permet de tracer la version en cours d'exécution |
| `docker:27-dind` | Service Docker-in-Docker pour que le job puisse exécuter `docker build` |
| `DOCKER_TLS_CERTDIR` | Fait partager les certificats TLS entre le client et le démon dind ; l'omettre provoque `Cannot connect to the Docker daemon` |
| `$CI_REGISTRY_*` | Prédéfinis ; le jeton du job se connecte automatiquement au registre du projet |
| `alpine/k8s` | Image avec `kubectl` et un shell ; épinglez le tag pour qu'il corresponde à la version du cluster |
| Namespace | Pris dans le contexte du kubeconfig, donc `-n` n'est pas nécessaire |

## Vérification

Poussez sur `main`, puis vérifiez **CI/CD -> Pipelines** (les deux étapes en vert) et le cluster :

```bash
kubectl -n <PROJECT_NAME> rollout history deployment/<PROJECT_NAME>-app
kubectl -n <PROJECT_NAME> get deploy <PROJECT_NAME>-app -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Le tag de l'image doit être égal au SHA court du dernier commit.

## Pièges courants

| Symptôme | Cause / solution |
|---|---|
| Runner hors ligne | `sudo systemctl restart gitlab-runner` ; vérifiez l'accès réseau à l'URL GitLab |
| `Cannot connect to the Docker daemon at tcp://docker:2375` | Runner non enregistré avec `--docker-privileged`, ou `DOCKER_TLS_CERTDIR` incohérent |
| `ImagePullBackOff` après le déploiement | Secret `gitlab-registry` ou `imagePullSecrets` manquant/incorrect ; `kubectl describe pod` affiche l'erreur de pull |
| `Unable to connect to the server` / `x509` | Le conteneur du job ne peut pas atteindre `<SERVER_IP>:6443` (UFW) ou le certificat ne contient pas cette IP (`tls-san`) |
| `forbidden: ... cannot patch resource` | Il manque un verbe au Role ou le Deployment se trouve dans un autre namespace |
| Variable vide dans le job | Variable `Protected` sur une branche non protégée |
| Déploiement réussi, ancienne page affichée | Cache du navigateur ; `rollout status` confirme le nouveau pod |

Suite : [Bases de Helm](../08-monitoring/helm-basics.md)
