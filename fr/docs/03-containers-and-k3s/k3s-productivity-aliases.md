# Alias kubectl et utilitaires de projet

Ajoute des alias Git/kubectl, la complétion `kubectl`, le changement de namespace et deux fonctions, `kstart <project>` et `kstop <project>`, qui appliquent ou suppriment tous les manifestes d'un répertoire de projet, avec complétion par Tab des noms de projets. Nécessite l'organisation décrite dans [Conventions de structure K8s](../05-deploying-projects/k8s-structure-conventions.md) : un répertoire de manifestes par projet.

Tout est placé dans `~/.bashrc`, entre la ligne Starship et la dernière ligne `ble-attach` (voir [productivité du shell](shell-productivity-starship.md) pour l'ordre). Sans ble.sh, ajoutez simplement à la fin du fichier.

## 1. Alias et complétion

```bash
# --- Alias Git ---
alias g='git'
alias gs='git status'
alias gc='git commit'
alias gch='git checkout'
alias gl='git pull'
alias gp='git push'

# --- Alias kubectl ---
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgi='kubectl get ingress'
alias kga='kubectl get all'
alias kd='kubectl describe'
alias kl='kubectl logs -f'
alias ke='kubectl exec -it'

# --- Complétion kubectl (aussi pour l'alias `k`) ---
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
```

| Alias | Équivaut à |
|---|---|
| `k` | `kubectl` |
| `kgp` / `kgs` / `kgi` / `kga` | `kubectl get pods` / `svc` / `ingress` / `all` |
| `kd <res> <name>` | `kubectl describe ...` |
| `kl <pod>` | `kubectl logs -f <pod>` |
| `ke <pod> -- sh` | `kubectl exec -it <pod> -- sh` |

Ajoutez `-n <namespace>` si nécessaire, par exemple `kgp -n kube-system`. Vérifiez qu'un nom est libre avec `type k`.

## 2. Changement de namespace

Définit un namespace comme valeur par défaut du contexte kubeconfig courant afin de pouvoir omettre `-n` :

```bash
# kns <namespace>  - définit le namespace par défaut ; kns sans argument affiche le namespace courant
kns() {
    if [ -z "$1" ]; then
        kubectl config view --minify --output 'jsonpath={..namespace}'; echo
        return
    fi
    kubectl config set-context --current --namespace="$1"
}
```

Réinitialisez avec `kns default`. Le module Kubernetes de Starship peut l'afficher en ajoutant `$namespace` à son `format` (`'on [⛵ $context/$namespace](dimmed green) '`).

## 3. `kstart` et `kstop`

Les projets se trouvent dans un seul répertoire, un sous-répertoire par projet, chacun contenant les fichiers YAML du projet :

```
~/k8s-infrastructure/projects/
    <PROJECT_NAME>/
        db.yaml
        app.yaml
        phpmyadmin.yaml
```

`kstart <PROJECT_NAME>` exécute `kubectl apply -R -f` sur le répertoire ; `kstop <PROJECT_NAME>` exécute `kubectl delete -R -f` (`-R` parcourt les sous-répertoires). Les noms longs peuvent recevoir des alias courts.

```bash
# --- Utilitaires de projet ---
K8S_PROJECTS_DIR="$HOME/k8s-infrastructure/projects"

# Associe des alias courts aux noms complets des répertoires de projets (ajoutez-les ici
# ET dans K8S_PROJECT_ALIASES ci-dessous, qui alimente la complétion par Tab).
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

Remarques :

- Les nouveaux répertoires de projets apparaissent automatiquement dans la complétion par Tab (le répertoire est listé à chaque Tab). Seuls les alias nécessitent une modification : ajoutez une branche `case` et le nom dans `K8S_PROJECT_ALIASES`.
- `kstop` supprime les Deployments, Services et Ingresses du projet, donc les Pods disparaissent. Les fichiers de base de données conservés dans des volumes `hostPath` restent sur le disque, de sorte qu'un `kstart` ultérieur restitue les données. Les namespaces et PersistentVolumeClaims déclarés dans le même répertoire sont également supprimés.
- Pour mettre en pause sans supprimer d'objets, réduisez plutôt le nombre de réplicas : `kubectl scale deployment --all --replicas=0` (et `--replicas=1` pour reprendre ; les Deployments à plusieurs réplicas nécessitent leur nombre d'origine).
- Pour arrêter tout le cluster : `sudo systemctl stop k3s` (et `sudo /usr/local/bin/k3s-killall.sh` pour tuer les processus de pods restants) ; `sudo systemctl start k3s` le relance.

Appliquez avec `exec bash`.

## Vérification

```bash
type k kstart kstop kns          # tous trouvés
k get node
kstart <Tab><Tab>                # liste les répertoires de projets et les alias
kstart <PROJECT_NAME> && kgp
kstop <PROJECT_NAME>
```

| Symptôme | Solution |
|---|---|
| `kstart: command not found` | Bloc absent de `~/.bashrc` ou shell non redémarré (`exec bash`) |
| `no objects passed to apply` / `does not exist` | Aucun fichier `.yaml` dans le répertoire du projet, ou nom/chemin incorrect ; `ls "$K8S_PROJECTS_DIR"` |
| Aucune suggestion Tab | Répertoire absent, ou ligne `complete -F ...` manquante |
| `syntax error near unexpected token` à la connexion | Une fonction a été collée de façon incomplète (`}` ou `;;` manquant) ; `bash -n ~/.bashrc` |
| `connection refused` / `permission denied` de kubectl | kubeconfig non configuré ; voir [Installation de K3s](k3s-install.md) |

Suite : [Clés SSH pour Git](../04-git-and-ide/ssh-keys-for-git.md)
