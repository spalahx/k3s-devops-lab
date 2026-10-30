# SSH-ключи для Git

Создаёт на сервере отдельные ключи ed25519 для GitLab/GitHub, подключает их через алиасы Host в `~/.ssh/config` и проверяет доступ через `ssh -T`. Ключи для Git-провайдера отдельны от ключа входа на сам сервер (тот хранится на ноутбуке, а его публичная часть лежит в `authorized_keys` сервера).

Ключей два, чтобы рабочий и личный аккаунты были изолированы (провайдер не принимает один ключ на двух аккаунтах). При единственном аккаунте создайте один ключ и пропустите второй.

## 1. Генерация ключей

```bash
ssh-keygen -t ed25519 -C "<GIT_WORK_EMAIL>" -f ~/.ssh/id_ed25519_work
ssh-keygen -t ed25519 -C "<GIT_PERSONAL_EMAIL>" -f ~/.ssh/id_ed25519_personal
```

| Флаг | Смысл |
|---|---|
| `-t ed25519` | Современный, короткий и быстрый тип ключа |
| `-C` | Комментарий, виден в списке ключей у провайдера |
| `-f` | Выходной файл; всегда задавайте разные имена, иначе второй ключ перезапишет первый |

Passphrase необязательна; пустая удобна, но любой, кто прочитает файл, сможет пользоваться ключом. С passphrase загружайте ключ в агент на сессию: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519_work`.

Результат в `~/.ssh/`: `id_ed25519_work` и `id_ed25519_personal` (приватные, никому не передавать) и файлы `.pub` (публичные).

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519_work ~/.ssh/id_ed25519_personal
```

## 2. Алиасы Host в `~/.ssh/config`

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

- `IdentitiesOnly yes` заставляет ssh предлагать только указанный ключ; без него сначала могут быть опробованы ключи агента или ключи по умолчанию, и провайдер аутентифицирует вас под чужим аккаунтом.
- Для GitLab используйте такой же блок с `HostName gitlab.com` (или именем собственного сервера и `Port <SSH_PORT>`, если порт не 22). Оставьте только используемые хосты.
- Remote-ы используют алиас вместо реального хоста:

```bash
git clone git@github-work:<ORG>/<REPO>.git
git remote set-url origin git@github-personal:<USER>/<REPO>.git
```

```bash
chmod 600 ~/.ssh/config
```

> **Note:** в [нескольких Git-идентичностях](multiple-git-identities.md) показан альтернативный вариант: ключ выбирается по каталогу через `core.sshCommand`; там remote-ы сохраняют реальное имя хоста и алиасы не нужны. Используйте одну схему на репозиторий.

## 3. Добавление публичных ключей в аккаунты

```bash
cat ~/.ssh/id_ed25519_work.pub
cat ~/.ssh/id_ed25519_personal.pub
```

Скопируйте каждый одной строкой (начинается с `ssh-ed25519`, без переносов) в соответствующий аккаунт:

| Провайдер | Где |
|---|---|
| GitHub | Settings > SSH and GPG keys > New SSH key |
| GitLab | Preferences > SSH Keys |

## Проверка

```bash
ssh -T git@github-work
ssh -T git@github-personal
```

Ожидается: GitHub `Hi <user>! You've successfully authenticated, but GitHub does not provide shell access.`; GitLab `Welcome to GitLab, @<user>!`. Отладка: `ssh -vT git@github-work`.

| Симптом | Решение |
|---|---|
| `Permission denied (publickey)` | Ключ не добавлен в аккаунт, не тот аккаунт или вставленный ключ разорван переносами |
| Аутентификация под другим пользователем | Нет `IdentitiesOnly yes` или remote всё ещё `git@github.com:` вместо алиаса |
| `Bad owner or permissions` | `chmod 600` на приватные ключи и config, `chmod 700 ~/.ssh` |
| `Could not resolve hostname github-work` | Опечатка в алиасе или `~/.ssh/config` не в домашнем каталоге пользователя сервера |

Next: [Несколько Git-идентичностей](multiple-git-identities.md)
