# Identités Git multiples

Fait choisir automatiquement à Git la bonne adresse e-mail et la bonne clé SSH selon le répertoire où se trouve un dépôt : tout ce qui est sous `~/workspace/work/` committe avec l'identité professionnelle, tout ce qui est sous `~/workspace/personal/` avec l'identité personnelle. Utilise les inclusions conditionnelles de Git (`includeIf`). À ignorer si vous n'avez qu'une seule identité.

Nécessite les clés de [Clés SSH pour Git](ssh-keys-for-git.md).

## 1. Organisation des répertoires

```bash
mkdir -p ~/workspace/work ~/workspace/personal
```

Clonez les dépôts dans le répertoire correspondant ; l'emplacement détermine l'identité. Le code source va dans `~/workspace/`, les manifestes Kubernetes dans un répertoire séparé `~/k8s-infrastructure/`.

## 2. `~/.gitconfig` global

```ini
[user]
    name = <GIT_USER_NAME>

[includeIf "gitdir:~/workspace/work/"]
    path = ~/.gitconfig-work

[includeIf "gitdir:~/workspace/personal/"]
    path = ~/.gitconfig-personal
```

`<GIT_USER_NAME>` est le nom affiché pour les commits. `includeIf "gitdir:..."` ne lit le fichier supplémentaire que si le `.git` du dépôt se trouve dans ce chemin. Le `/` final est obligatoire : il correspond au répertoire et à tout ce qu'il contient.

## 3. Fichiers d'identité

`~/.gitconfig-work` :

```ini
[user]
    email = <GIT_WORK_EMAIL>
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519_work -o IdentitiesOnly=yes
```

`~/.gitconfig-personal` :

```ini
[user]
    email = <GIT_PERSONAL_EMAIL>
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519_personal -o IdentitiesOnly=yes
```

- `core.sshCommand` indique à Git quelle clé privée utiliser pour fetch/push. `IdentitiesOnly=yes` empêche ssh de proposer aussi les clés de l'agent ou par défaut (ce qui peut vous authentifier avec le mauvais compte).
- Avec ce schéma, les remotes conservent le véritable hôte (`git@github.com:<ORG>/<REPO>.git`) ; les alias Host de la page précédente ne sont pas nécessaires pour ces dépôts.
- Les fichiers d'identité se trouvent dans le répertoire personnel, en dehors des dépôts, ils ne risquent donc jamais de se retrouver dans un dépôt.

## Vérification

```bash
cd ~/workspace/work
git clone git@github.com:<ORG>/<REPO>.git && cd <REPO>
git config user.email                       # <GIT_WORK_EMAIL>
git config --show-origin --get-all user.email
git config core.sshCommand

cd ~/workspace/personal/<OTHER_REPO>
git config user.email                       # <GIT_PERSONAL_EMAIL>
```

`--show-origin` affiche le fichier qui a fourni la valeur.

| Symptôme | Solution |
|---|---|
| `user.email` vide | Hors d'un dépôt, ou le chemin dans `includeIf` ne correspond pas (`/` final manquant, répertoire avec lien symbolique) ; essayez le chemin absolu, par exemple `gitdir:/home/<SERVER_USER>/workspace/work/` |
| Bon e-mail, mauvaise clé/compte | `sshCommand` absent, ou le remote utilise un alias/hôte qui le remplace |
| Chemins insensibles à la casse nécessaires | Utilisez `gitdir/i:` au lieu de `gitdir:` |
| Dépôt en dehors des deux répertoires | Définissez localement : `git config user.email <GIT_PERSONAL_EMAIL>` |
| Les anciens commits ont le mauvais e-mail | L'identité est appliquée au moment du commit ; Git relit les configurations à chaque commande, aucun redémarrage n'est nécessaire |

Suite : [IDE via SSH](ide-remote-ssh.md)
