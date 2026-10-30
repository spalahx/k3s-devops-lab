# Multiple Git Identities

Makes Git pick the right e-mail and SSH key automatically from the directory a repository lives in: everything under `~/workspace/work/` commits as the work identity, everything under `~/workspace/personal/` as the personal one. Uses Git's conditional includes (`includeIf`). Skip if you have a single identity.

Requires the keys from [SSH keys for Git](ssh-keys-for-git.md).

## 1. Directory layout

```bash
mkdir -p ~/workspace/work ~/workspace/personal
```

Clone repositories into the matching directory; the location decides the identity. Source code goes in `~/workspace/`, Kubernetes manifests in a separate `~/k8s-infrastructure/`.

## 2. Global `~/.gitconfig`

```ini
[user]
    name = <GIT_USER_NAME>

[includeIf "gitdir:~/workspace/work/"]
    path = ~/.gitconfig-work

[includeIf "gitdir:~/workspace/personal/"]
    path = ~/.gitconfig-personal
```

`<GIT_USER_NAME>` is the display name for commits. `includeIf "gitdir:..."` reads the extra file only when the repository's `.git` is inside that path. The trailing `/` is required: it matches the directory and everything below it.

## 3. Identity files

`~/.gitconfig-work`:

```ini
[user]
    email = <GIT_WORK_EMAIL>
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519_work -o IdentitiesOnly=yes
```

`~/.gitconfig-personal`:

```ini
[user]
    email = <GIT_PERSONAL_EMAIL>
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519_personal -o IdentitiesOnly=yes
```

- `core.sshCommand` tells Git which private key to use for fetch/push. `IdentitiesOnly=yes` prevents ssh from also offering agent or default keys (which can authenticate you as the wrong account).
- With this scheme remotes keep the real host (`git@github.com:<ORG>/<REPO>.git`); the Host aliases from the previous page are not needed for these repositories.
- The identity files sit in the home directory, outside the repositories, so they never end up in a repo.

## Verify

```bash
cd ~/workspace/work
git clone git@github.com:<ORG>/<REPO>.git && cd <REPO>
git config user.email                       # <GIT_WORK_EMAIL>
git config --show-origin --get-all user.email
git config core.sshCommand

cd ~/workspace/personal/<OTHER_REPO>
git config user.email                       # <GIT_PERSONAL_EMAIL>
```

`--show-origin` prints which file supplied the value.

| Symptom | Fix |
|---|---|
| Empty `user.email` | Not inside a repository, or the path in `includeIf` does not match (missing trailing `/`, symlinked directory); try the absolute path, e.g. `gitdir:/home/<SERVER_USER>/workspace/work/` |
| Right e-mail, wrong key/account | `sshCommand` missing, or the remote uses an alias/host that overrides it |
| Case-insensitive paths needed | Use `gitdir/i:` instead of `gitdir:` |
| Repository outside both directories | Set locally: `git config user.email <GIT_PERSONAL_EMAIL>` |
| Old commits have the wrong e-mail | Identity is applied at commit time; Git reads configs on every command, no restart needed |

Next: [IDE over SSH](ide-remote-ssh.md)
