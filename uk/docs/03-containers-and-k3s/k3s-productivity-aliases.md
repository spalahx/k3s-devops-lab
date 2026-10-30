# Аліаси kubectl і помічники для проєктів

Додає аліаси Git/kubectl, автодоповнення `kubectl`, перемикання просторів імен і дві функції, `kstart <project>` та `kstop <project>`, які застосовують або видаляють усі маніфести каталогу проєкту, з автодоповненням назв проєктів за Tab. Потребує структури з [Угод щодо структури K8s](../05-deploying-projects/k8s-structure-conventions.md): один каталог маніфестів на проєкт.

Усе додається в `~/.bashrc` між рядком Starship і завершальним рядком `ble-attach` (порядок див. у [продуктивності оболонки](shell-productivity-starship.md)). Без ble.sh просто допишіть у кінець файлу.

## 1. Аліаси та автодоповнення

```bash
# --- Git aliases ---
alias g='git'
alias gs='git status'
alias gc='git commit'
alias gch='git checkout'
alias gl='git pull'
alias gp='git push'

# --- kubectl aliases ---
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgi='kubectl get ingress'
alias kga='kubectl get all'
alias kd='kubectl describe'
alias kl='kubectl logs -f'
alias ke='kubectl exec -it'

# --- kubectl completion (also for the `k` alias) ---
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
```

| Аліас | Розгортається в |
|---|---|
| `k` | `kubectl` |
| `kgp` / `kgs` / `kgi` / `kga` | `kubectl get pods` / `svc` / `ingress` / `all` |
| `kd <res> <name>` | `kubectl describe ...` |
| `kl <pod>` | `kubectl logs -f <pod>` |
| `ke <pod> -- sh` | `kubectl exec -it <pod> -- sh` |

Додавайте `-n <namespace>` за потреби, наприклад `kgp -n kube-system`. Перевірте, що ім'я вільне, командою `type k`.

## 2. Перемикання простору імен

Зробіть простір імен типовим для поточного контексту kubeconfig, щоб `-n` можна було не вказувати:

```bash
# kns <namespace>  - set default namespace; kns without args shows the current one
kns() {
    if [ -z "$1" ]; then
        kubectl config view --minify --output 'jsonpath={..namespace}'; echo
        return
    fi
    kubectl config set-context --current --namespace="$1"
}
```

Скидання: `kns default`. Модуль Kubernetes у Starship може його показувати, якщо додати `$namespace` до його `format` (`'on [⛵ $context/$namespace](dimmed green) '`).

## 3. `kstart` і `kstop`

Проєкти лежать в одному каталозі, по одному підкаталогу на проєкт, у кожному — YAML-файли цього проєкту:

```
~/k8s-infrastructure/projects/
    <PROJECT_NAME>/
        db.yaml
        app.yaml
        phpmyadmin.yaml
```

`kstart <PROJECT_NAME>` виконує `kubectl apply -R -f` для каталогу; `kstop <PROJECT_NAME>` виконує `kubectl delete -R -f` (`-R` заходить у підкаталоги). Довгим назвам можна дати короткі аліаси.

```bash
# --- Project helpers ---
K8S_PROJECTS_DIR="$HOME/k8s-infrastructure/projects"

# Map short aliases to full project directory names (add new ones here
# AND in K8S_PROJECT_ALIASES below, which feeds Tab completion).
K8S_PROJECT_ALIASES="blog2 shop"
_resolve_project_name() {
    case "$1" in
        blog2) echo "my-long-blog-project" ;;
        shop)  echo "online-shop" ;;
        *)     echo "$1" ;;
    esac
}

kstart() {
    if [ -z "$1" ]; then
        echo "Usage: kstart <project|alias>"
        return 1
    fi
    local project
    project=$(_resolve_project_name "$1")
    kubectl apply -R -f "$K8S_PROJECTS_DIR/$project"
}

kstop() {
    if [ -z "$1" ]; then
        echo "Usage: kstop <project|alias>"
        return 1
    fi
    local project
    project=$(_resolve_project_name "$1")
    kubectl delete -R -f "$K8S_PROJECTS_DIR/$project"
}

_k3s_projects_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [ -d "$K8S_PROJECTS_DIR" ]; then
        local real_dirs
        real_dirs=$(ls "$K8S_PROJECTS_DIR")
        COMPREPLY=( $(compgen -W "$real_dirs $K8S_PROJECT_ALIASES" -- "$cur") )
    fi
}
complete -F _k3s_projects_completion kstart kstop
```

Примітки:

- Нові каталоги проєктів з'являються в автодоповненні за Tab автоматично (вміст каталогу зчитується при кожному натисканні Tab). Редагувати потрібно лише аліаси: додайте гілку `case` і назву в `K8S_PROJECT_ALIASES`.
- `kstop` видаляє Deployment, Service та Ingress проєкту, тож поди зникають. Файли бази даних у томах `hostPath` залишаються на диску, тому пізніший `kstart` повертає дані. Простори імен і PersistentVolumeClaim, оголошені в тому самому каталозі, теж видаляються.
- Щоб призупинити без видалення об'єктів, замість цього масштабуйте: `kubectl scale deployment --all --replicas=0` (і `--replicas=1`, щоб відновити; для Deployment з кількома репліками потрібна їхня початкова кількість).
- Щоб зупинити весь кластер: `sudo systemctl stop k3s` (і `sudo /usr/local/bin/k3s-killall.sh`, щоб завершити решту процесів подів); `sudo systemctl start k3s` повертає його.

Застосуйте через `exec bash`.

## Перевірка

```bash
type k kstart kstop kns          # all found
k get node
kstart <Tab><Tab>                # lists project directories and aliases
kstart <PROJECT_NAME> && kgp
kstop <PROJECT_NAME>
```

| Симптом | Рішення |
|---|---|
| `kstart: command not found` | Блока немає в `~/.bashrc` або оболонку не перезапущено (`exec bash`) |
| `no objects passed to apply` / `does not exist` | У каталозі проєкту немає файлів `.yaml`, або хибні ім'я/шлях; `ls "$K8S_PROJECTS_DIR"` |
| Немає підказок за Tab | Каталог відсутній або немає рядка `complete -F ...` |
| `syntax error near unexpected token` під час входу | Функцію вставлено неповністю (бракує `}` або `;;`); `bash -n ~/.bashrc` |
| `connection refused` / `permission denied` від kubectl | kubeconfig не налаштовано; див. [Встановлення K3s](k3s-install.md) |

Далі: [SSH-ключі для Git](../04-git-and-ide/ssh-keys-for-git.md)
