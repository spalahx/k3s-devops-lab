# Conventions de répertoires et de nommage : code et manifestes

Définit une organisation en deux dépôts sur le serveur : le code des projets dans `~/workspace`, les manifestes Kubernetes dans `~/k8s-infrastructure`. À utiliser avant de déployer le premier projet ; à ignorer uniquement si vous n'avez qu'un seul projet avec ses manifestes dans son propre dépôt.

## Organisation

```
~/workspace/<PROJECT_GROUP>/              # code uniquement (PHP/JS/thèmes), un dépôt Git par projet
├── <PROJECT_NAME>/
│   ├── k8s-local/                        # local uniquement : conf nginx, mysql-data (exclu de Git)
│   └── ...
└── <OTHER_PROJECT>/

~/k8s-infrastructure/                     # manifestes uniquement, son propre dépôt Git
├── system/                               # à l'échelle du cluster : réglages Traefik, supervision
│   ├── ingress/
│   └── monitoring/
└── projects/
    └── <PROJECT_GROUP>/
        ├── <PROJECT_NAME>/
        │   ├── db.yaml
        │   ├── phpmyadmin.yaml
        │   └── app.yaml
        └── <OTHER_PROJECT>/
            └── app.yaml
```

| Répertoire | Contenu | Modifications |
|---|---|---|
| `~/workspace/...` | Code applicatif, historique dans le Git du projet | Plusieurs fois par jour |
| `~/k8s-infrastructure/system/` | Configuration globale au cluster, partagée par tous les projets | Rarement |
| `~/k8s-infrastructure/projects/` | Un répertoire par projet déployé | Lors d'un changement de noms d'hôte, de ressources ou d'images |

Raisons de cette séparation : le code et la configuration d'exécution évoluent à des rythmes différents, appartiennent à des dépôts et à des responsables différents, et les manifestes peuvent référencer des détails d'infrastructure (noms d'hôte, tailles de ressources) qui ne doivent pas figurer dans le dépôt de l'application.

## Règles de nommage

1. Les noms de répertoires de projet sont **identiques** dans les deux arborescences (`~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>` et `~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>`). Les helpers shell tels que `kstart`/`kstop` (voir [alias K3s](../03-containers-and-k3s/k3s-productivity-aliases.md)) s'appuient dessus pour retrouver les manifestes à partir d'un nom de projet court.
2. Chaque nom d'objet porte le préfixe du projet ; n'utilisez jamais `db`, `app`, `redis` seuls :

   | Objet | Nom |
   |---|---|
   | Namespace | `<PROJECT_NAME>` |
   | Deployments | `<PROJECT_NAME>-app`, `<PROJECT_NAME>-db`, `<PROJECT_NAME>-phpmyadmin` |
   | Services | `<PROJECT_NAME>-service`, `<PROJECT_NAME>-db-service`, `<PROJECT_NAME>-phpmyadmin-svc` |
   | Labels | `app: <PROJECT_NAME>`, `app: <PROJECT_NAME>-db` |
   | Noms d'hôte | `<PROJECT_NAME>.<DOMAIN_BASE>`, `<PROJECT_NAME>-pma.<DOMAIN_BASE>` |
   | Image locale | `<PROJECT_NAME>-php:latest` |

3. Les noms de fichiers n'impliquent aucun ordre. `kubectl apply -R -f <dir>` applique tout en une fois ; une application qui démarre avant la base de données redémarre simplement jusqu'à ce que la base soit prête.

## Un fichier ou plusieurs

| Variante | À utiliser quand |
|---|---|
| Un seul `app.yaml` (objets séparés par `---`) | Projet à un seul composant |
| `deployment.yaml` / `service.yaml` / `ingress.yaml` | Groupe de petits projets simples |
| `db.yaml`, `phpmyadmin.yaml`, `app.yaml` | Projet multi-composants (WordPress + base + interface d'administration) ; permet de redémarrer ou supprimer un composant isolément |

Kubernetes traite toutes les variantes de la même façon. Fichiers WordPress prêts à l'emploi : [`examples/wordpress/`](../../examples/wordpress/).

## Namespaces

Un namespace par projet : `kubectl create namespace <PROJECT_NAME>`. Le namespace apporte l'isolation des noms (deux projets peuvent chacun contenir un Service nommé `db`), un nettoyage en une seule commande (`kubectl delete namespace`) et des quotas par projet. Renseignez `metadata.namespace` dans chaque manifeste, afin que `kubectl apply -f` ne dépende pas du contexte courant. Les composants de niveau cluster (Traefik, supervision) restent dans leurs propres namespaces et ne sont pas gérés ici.

## Où modifier quoi

| Tâche | Emplacement |
|---|---|
| Modifier le code applicatif | `~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/` |
| Changer le nom d'hôte, les replicas, les ressources | `~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>/app.yaml` |
| Changer les réglages de la base | `.../db.yaml` |
| Traefik / supervision globaux | `~/k8s-infrastructure/system/` |

## Créer le squelette

```bash
mkdir -p ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/{nginx,mysql-data}
mkdir -p ~/k8s-infrastructure/system/{ingress,monitoring}
mkdir -p ~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>
cd ~/k8s-infrastructure && git init
```

Excluez les données locales du dépôt de code sans toucher à son `.gitignore` partagé :

```bash
printf 'k8s-local/\nwp-cli.phar\n*.sql\n' >> ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/.git/info/exclude
```

> **Avertissement :** modifier le code dans `~/workspace` ne change pas à lui seul un conteneur en cours d'exécution. Avec un code monté via `hostPath`, la modification est visible immédiatement (redémarrez seulement si opcache la met en cache) ; avec un code intégré à une image, vous devez reconstruire l'image puis lancer `kubectl rollout restart`.

## Vérifier

```bash
ls ~/k8s-infrastructure/projects/<PROJECT_GROUP>/<PROJECT_NAME>/
cd ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME> && git status --short   # k8s-local/ ne doit pas apparaître
```

Si `kubectl apply -R -f <dir>` affiche `no objects passed to apply`, le répertoire ne contient aucun fichier `.yaml` ou le chemin est incorrect.

Suite : [Guide de déploiement générique](generic-deployment-walkthrough.md)
