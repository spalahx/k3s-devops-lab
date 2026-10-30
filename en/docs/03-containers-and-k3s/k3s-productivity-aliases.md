# kubectl Aliases and Project Helpers

Adds Git/kubectl aliases, `kubectl` completion, namespace switching and two functions, `kstart <project>` and `kstop <project>`, that apply or delete all manifests of a project directory, with Tab completion of project names. Needs the layout from [K8s structure conventions](../05-deploying-projects/k8s-structure-conventions.md): one directory of manifests per project.

Everything goes into `~/.bashrc` between the Starship line and the final `ble-attach` line (see [shell productivity](shell-productivity-starship.md) for the order). Without ble.sh, simply append to the end of the file.

## 1. Aliases and completion

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

| Alias | Expands to |
|---|---|
| `k` | `kubectl` |
| `kgp` / `kgs` / `kgi` / `kga` | `kubectl get pods` / `svc` / `ingress` / `all` |
| `kd <res> <name>` | `kubectl describe ...` |
| `kl <pod>` | `kubectl logs -f <pod>` |
| `ke <pod> -- sh` | `kubectl exec -it <pod> -- sh` |

Add `-n <namespace>` where needed, e.g. `kgp -n kube-system`. Check that a name is free with `type k`.

## 2. Namespace switching

Make a namespace the default for the current kubeconfig context so `-n` can be omitted:

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

Reset with `kns default`. The Starship Kubernetes module can show it by adding `$namespace` to its `format` (`'on [⛵ $context/$namespace](dimmed green) '`).

## 3. `kstart` and `kstop`

Projects live in one directory, one subdirectory per project, each holding that project's YAML files:

```
~/k8s-infrastructure/projects/
    <PROJECT_NAME>/
        db.yaml
        app.yaml
        phpmyadmin.yaml
```

`kstart <PROJECT_NAME>` runs `kubectl apply -R -f` on the directory; `kstop <PROJECT_NAME>` runs `kubectl delete -R -f` (`-R` recurses into subdirectories). Long names can get short aliases.

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

Notes:

- New project directories appear in Tab completion automatically (the directory is listed on each Tab). Only aliases need editing: add a `case` branch and the name to `K8S_PROJECT_ALIASES`.
- `kstop` deletes the Deployments, Services and Ingresses of the project, so the Pods disappear. Database files kept in `hostPath` volumes stay on disk, so `kstart` later brings the data back. Namespaces and PersistentVolumeClaims declared in the same directory are deleted too.
- To pause without deleting objects, scale instead: `kubectl scale deployment --all --replicas=0` (and `--replicas=1` to resume; multi-replica Deployments need their original count).
- To stop the whole cluster: `sudo systemctl stop k3s` (and `sudo /usr/local/bin/k3s-killall.sh` to kill leftover pod processes); `sudo systemctl start k3s` brings it back.

Apply with `exec bash`.

## Verify

```bash
type k kstart kstop kns          # all found
k get node
kstart <Tab><Tab>                # lists project directories and aliases
kstart <PROJECT_NAME> && kgp
kstop <PROJECT_NAME>
```

| Symptom | Fix |
|---|---|
| `kstart: command not found` | Block not in `~/.bashrc` or shell not restarted (`exec bash`) |
| `no objects passed to apply` / `does not exist` | No `.yaml` files in the project directory, or wrong name/path; `ls "$K8S_PROJECTS_DIR"` |
| No Tab suggestions | Directory missing, or the `complete -F ...` line is absent |
| `syntax error near unexpected token` on login | A function was pasted incompletely (missing `}` or `;;`); `bash -n ~/.bashrc` |
| `connection refused` / `permission denied` from kubectl | kubeconfig not set up; see [K3s install](k3s-install.md) |

Next: [SSH keys for Git](../04-git-and-ide/ssh-keys-for-git.md)
