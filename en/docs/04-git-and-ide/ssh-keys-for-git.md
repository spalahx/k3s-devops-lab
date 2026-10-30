# SSH Keys for Git

Creates dedicated ed25519 SSH keys on the server for GitLab/GitHub, wires them up through `~/.ssh/config` Host aliases and verifies access with `ssh -T`. Keys for the Git provider are separate from the key you use to log in to the server itself (that one lives on the laptop and its public half in the server's `authorized_keys`).

Two keys are created so that work and personal accounts stay isolated (a provider refuses the same key on two accounts). With a single account, create one key and skip the second.

## 1. Generate keys

```bash
ssh-keygen -t ed25519 -C "<GIT_WORK_EMAIL>" -f ~/.ssh/id_ed25519_work
ssh-keygen -t ed25519 -C "<GIT_PERSONAL_EMAIL>" -f ~/.ssh/id_ed25519_personal
```

| Flag | Meaning |
|---|---|
| `-t ed25519` | Modern, short, fast key type |
| `-C` | Comment shown in the provider's key list |
| `-f` | Output file; always give distinct names, otherwise the second key overwrites the first |

A passphrase is optional; an empty one is convenient but means anyone who reads the file can use the key. With a passphrase, load it into an agent per session: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519_work`.

Result in `~/.ssh/`: `id_ed25519_work` and `id_ed25519_personal` (private, never share) plus the `.pub` files (public).

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519_work ~/.ssh/id_ed25519_personal
```

## 2. Host aliases in `~/.ssh/config`

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

- `IdentitiesOnly yes` forces ssh to offer only the listed key; without it an agent or default keys may be tried first and the provider authenticates you as the wrong account.
- For GitLab use the same block with `HostName gitlab.com` (or your self-hosted hostname, plus `Port <SSH_PORT>` if it is not 22). Keep only the hosts you use.
- Remotes then use the alias instead of the real host:

```bash
git clone git@github-work:<ORG>/<REPO>.git
git remote set-url origin git@github-personal:<USER>/<REPO>.git
```

```bash
chmod 600 ~/.ssh/config
```

> **Note:** [multiple Git identities](multiple-git-identities.md) shows an alternative that selects the key per directory with `core.sshCommand`; there remotes keep the real host name and no aliases are needed. Use one scheme per repository.

## 3. Add the public keys to the accounts

```bash
cat ~/.ssh/id_ed25519_work.pub
cat ~/.ssh/id_ed25519_personal.pub
```

Copy each as one line (starts with `ssh-ed25519`, no line breaks) into the matching account:

| Provider | Location |
|---|---|
| GitHub | Settings > SSH and GPG keys > New SSH key |
| GitLab | Preferences > SSH Keys |

## Verify

```bash
ssh -T git@github-work
ssh -T git@github-personal
```

Expected: GitHub `Hi <user>! You've successfully authenticated, but GitHub does not provide shell access.`; GitLab prints `Welcome to GitLab, @<user>!`. Debug with `ssh -vT git@github-work`.

| Symptom | Fix |
|---|---|
| `Permission denied (publickey)` | Key not added to the account, wrong account, or the pasted key was broken across lines |
| Authenticated as the wrong user | `IdentitiesOnly yes` missing, or a remote still uses `git@github.com:` instead of the alias |
| `Bad owner or permissions` | `chmod 600` on the private keys and config, `chmod 700 ~/.ssh` |
| `Could not resolve hostname github-work` | Alias typo or `~/.ssh/config` not in the server user's home |

Next: [Multiple Git identities](multiple-git-identities.md)
