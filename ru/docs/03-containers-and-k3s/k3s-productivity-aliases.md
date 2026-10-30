# Алиасы kubectl и хелперы проектов

Добавляет алиасы Git/kubectl, автодополнение `kubectl`, переключение namespace и две функции, `kstart <project>` и `kstop <project>`, которые применяют или удаляют все манифесты каталога проекта, с автодополнением имён проектов по Tab. Требует структуры из [Конвенции структуры K8s](../05-deploying-projects/k8s-structure-conventions.md): один каталог манифестов на проект.

Всё добавляется в `~/.bashrc` между строкой Starship и финальной строкой `ble-attach` (порядок см. в [продуктивности шелла](shell-productivity-starship.md)). Без ble.sh просто допишите в конец файла.

## 1. Алиасы и автодополнение

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

# --- автодополнение kubectl (в том числе для алиаса `k`) ---
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
```

| Алиас | Разворачивается в |
|---|---|
| `k` | `kubectl` |
| `kgp` / `kgs` / `kgi` / `kga` | `kubectl get pods` / `svc` / `ingress` / `all` |
| `kd <res> <name>` | `kubectl describe ...` |
| `kl <pod>` | `kubectl logs -f <pod>` |
| `ke <pod> -- sh` | `kubectl exec -it <pod> -- sh` |

При необходимости добавляйте `-n <namespace>`, например `kgp -n kube-system`. Свободно ли имя, проверяется `type k`.

## 2. Переключение namespace

Сделать namespace по умолчанию для текущего контекста kubeconfig, чтобы не писать `-n`:

```bash
# kns <namespace>  - задать namespace по умолчанию; без аргумента показывает текущий
kns() {
    if [ -z "$1" ]; then
        kubectl config view --minify --output 'jsonpath={..namespace}'; echo
        return
    fi
    kubectl config set-context --current --namespace="$1"
}
```

Сброс: `kns default`. Модуль Kubernetes в Starship может показывать namespace, если добавить `$namespace` в `format` (`'on [⛵ $context/$namespace](dimmed green) '`).

## 3. `kstart` и `kstop`

Проекты лежат в одном каталоге, по подкаталогу на проект, в каждом YAML-файлы этого проекта:

```
~/k8s-infrastructure/projects/
    <PROJECT_NAME>/
        db.yaml
        app.yaml
        phpmyadmin.yaml
```

`kstart <PROJECT_NAME>` выполняет `kubectl apply -R -f` для каталога; `kstop <PROJECT_NAME>` выполняет `kubectl delete -R -f` (`-R` обходит подкаталоги). Для длинных имён можно завести короткие алиасы.

```bash
# --- Хелперы проектов ---
K8S_PROJECTS_DIR="$HOME/k8s-infrastructure/projects"

# Короткие алиасы -> полные имена каталогов проектов (новые добавляйте здесь
# И в K8S_PROJECT_ALIASES ниже, который используется для автодополнения).
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

Примечания:

- Новые каталоги проектов появляются в автодополнении сами (каталог читается при каждом Tab). Править нужно только алиасы: добавить ветку в `case` и имя в `K8S_PROJECT_ALIASES`.
- `kstop` удаляет Deployment, Service и Ingress проекта, поэтому Pod исчезают. Файлы базы данных в томах `hostPath` остаются на диске, и последующий `kstart` возвращает данные. Namespace и PersistentVolumeClaim, описанные в том же каталоге, тоже удаляются.
- Чтобы приостановить проект, не удаляя объекты, масштабируйте: `kubectl scale deployment --all --replicas=0` (и `--replicas=1` для запуска; для Deployment с несколькими репликами нужно исходное число).
- Остановить весь кластер: `sudo systemctl stop k3s` (и `sudo /usr/local/bin/k3s-killall.sh`, чтобы убить оставшиеся процессы подов); `sudo systemctl start k3s` запускает его обратно.

Применить: `exec bash`.

## Проверка

```bash
type k kstart kstop kns          # все найдены
k get node
kstart <Tab><Tab>                # список каталогов проектов и алиасов
kstart <PROJECT_NAME> && kgp
kstop <PROJECT_NAME>
```

| Симптом | Решение |
|---|---|
| `kstart: command not found` | Блока нет в `~/.bashrc` или шелл не перезапущен (`exec bash`) |
| `no objects passed to apply` / `does not exist` | В каталоге проекта нет `.yaml` или неверное имя/путь; `ls "$K8S_PROJECTS_DIR"` |
| Нет подсказок по Tab | Нет каталога или отсутствует строка `complete -F ...` |
| `syntax error near unexpected token` при входе | Функция вставлена не полностью (нет `}` или `;;`); `bash -n ~/.bashrc` |
| `connection refused` / `permission denied` от kubectl | Не настроен kubeconfig; см. [Установка K3s](k3s-install.md) |

Next: [SSH-ключи для Git](../04-git-and-ide/ssh-keys-for-git.md)
