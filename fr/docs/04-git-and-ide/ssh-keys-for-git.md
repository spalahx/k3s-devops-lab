# Clés SSH pour Git

Crée sur le serveur des clés SSH ed25519 dédiées pour GitLab/GitHub, les relie via des alias Host dans `~/.ssh/config` et vérifie l'accès avec `ssh -T`. Les clés pour le fournisseur Git sont distinctes de la clé que vous utilisez pour vous connecter au serveur lui-même (celle-ci se trouve sur le portable et sa moitié publique dans `authorized_keys` du serveur).

Deux clés sont créées afin que les comptes professionnel et personnel restent isolés (un fournisseur refuse la même clé sur deux comptes). Avec un seul compte, créez une seule clé et ignorez la seconde.

## 1. Générer les clés

```bash
ssh-keygen -t ed25519 -C "<GIT_WORK_EMAIL>" -f ~/.ssh/id_ed25519_work
ssh-keygen -t ed25519 -C "<GIT_PERSONAL_EMAIL>" -f ~/.ssh/id_ed25519_personal
```

| Option | Signification |
|---|---|
| `-t ed25519` | Type de clé moderne, courte et rapide |
| `-C` | Commentaire affiché dans la liste des clés du fournisseur |
| `-f` | Fichier de sortie ; donnez toujours des noms distincts, sinon la seconde clé écrase la première |

Une phrase secrète est facultative ; une phrase vide est pratique mais signifie que quiconque lit le fichier peut utiliser la clé. Avec une phrase secrète, chargez la clé dans un agent à chaque session : `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519_work`.

Résultat dans `~/.ssh/` : `id_ed25519_work` et `id_ed25519_personal` (privées, ne les partagez jamais) ainsi que les fichiers `.pub` (publics).

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519_work ~/.ssh/id_ed25519_personal
```

## 2. Alias Host dans `~/.ssh/config`

```
Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes

Host github-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal
    IdentitiesOnly yes
```

- `IdentitiesOnly yes` force ssh à ne proposer que la clé indiquée ; sans cela, une clé d'agent ou par défaut peut être essayée en premier et le fournisseur vous authentifie avec le mauvais compte.
- Pour GitLab, utilisez le même bloc avec `HostName gitlab.com` (ou le nom d'hôte de votre instance auto-hébergée, plus `Port <SSH_PORT>` s'il n'est pas 22). Ne conservez que les hôtes que vous utilisez.
- Les remotes utilisent alors l'alias au lieu du véritable hôte :

```bash
git clone git@github-work:<ORG>/<REPO>.git
git remote set-url origin git@github-personal:<USER>/<REPO>.git
```

```bash
chmod 600 ~/.ssh/config
```

> **Note :** [Identités Git multiples](multiple-git-identities.md) présente une alternative qui sélectionne la clé par répertoire avec `core.sshCommand` ; dans ce cas, les remotes conservent le vrai nom d'hôte et aucun alias n'est nécessaire. Utilisez un seul schéma par dépôt.

## 3. Ajouter les clés publiques aux comptes

```bash
cat ~/.ssh/id_ed25519_work.pub
cat ~/.ssh/id_ed25519_personal.pub
```

Copiez chacune sur une seule ligne (elle commence par `ssh-ed25519`, sans saut de ligne) dans le compte correspondant :

| Fournisseur | Emplacement |
|---|---|
| GitHub | Settings > SSH and GPG keys > New SSH key |
| GitLab | Preferences > SSH Keys |

## Vérification

```bash
ssh -T git@github-work
ssh -T git@github-personal
```

Résultat attendu : GitHub `Hi <user>! You've successfully authenticated, but GitHub does not provide shell access.` ; GitLab affiche `Welcome to GitLab, @<user>!`. Débogage avec `ssh -vT git@github-work`.

| Symptôme | Solution |
|---|---|
| `Permission denied (publickey)` | Clé non ajoutée au compte, mauvais compte, ou clé collée coupée sur plusieurs lignes |
| Authentifié avec le mauvais utilisateur | `IdentitiesOnly yes` manquant, ou un remote utilise encore `git@github.com:` au lieu de l'alias |
| `Bad owner or permissions` | `chmod 600` sur les clés privées et le fichier config, `chmod 700 ~/.ssh` |
| `Could not resolve hostname github-work` | Faute de frappe dans l'alias, ou `~/.ssh/config` absent du répertoire personnel de l'utilisateur du serveur |

Suite : [Identités Git multiples](multiple-git-identities.md)
