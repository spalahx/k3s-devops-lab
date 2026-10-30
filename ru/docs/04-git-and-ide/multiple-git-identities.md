# Несколько Git-идентичностей

Заставляет Git автоматически выбирать нужные e-mail и SSH-ключ по каталогу, в котором лежит репозиторий: всё под `~/workspace/work/` коммитится от рабочей идентичности, всё под `~/workspace/personal/` от личной. Используются условные подключения Git (`includeIf`). Пропустите, если идентичность одна.

Нужны ключи из [SSH-ключей для Git](ssh-keys-for-git.md).

## 1. Структура каталогов

```bash
mkdir -p ~/workspace/work ~/workspace/personal
```

Клонируйте репозитории в соответствующий каталог; идентичность определяется расположением. Исходный код лежит в `~/workspace/`, манифесты Kubernetes в отдельном `~/k8s-infrastructure/`.

## 2. Глобальный `~/.gitconfig`

```ini
[user]
    name = <GIT_USER_NAME>

[includeIf "gitdir:~/workspace/work/"]
    path = ~/.gitconfig-work

[includeIf "gitdir:~/workspace/personal/"]
    path = ~/.gitconfig-personal
```

`<GIT_USER_NAME>` это отображаемое имя в коммитах. `includeIf "gitdir:..."` подключает дополнительный файл, только если `.git` репозитория находится внутри этого пути. Завершающий `/` обязателен: он означает каталог и всё внутри него.

## 3. Файлы идентичностей

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

- `core.sshCommand` сообщает Git, какой приватный ключ использовать для fetch/push. `IdentitiesOnly=yes` не даёт ssh предлагать ключи агента и ключи по умолчанию (из-за них можно авторизоваться не под тем аккаунтом).
- В этой схеме remote-ы сохраняют реальный хост (`git@github.com:<ORG>/<REPO>.git`); алиасы Host с предыдущей страницы для этих репозиториев не нужны.
- Файлы идентичностей лежат в домашнем каталоге, вне репозиториев, поэтому не попадают в репозиторий.

## Проверка

```bash
cd ~/workspace/work
git clone git@github.com:<ORG>/<REPO>.git && cd <REPO>
git config user.email                       # <GIT_WORK_EMAIL>
git config --show-origin --get-all user.email
git config core.sshCommand

cd ~/workspace/personal/<OTHER_REPO>
git config user.email                       # <GIT_PERSONAL_EMAIL>
```

`--show-origin` показывает, из какого файла взято значение.

| Симптом | Решение |
|---|---|
| Пустой `user.email` | Вы не внутри репозитория или путь в `includeIf` не совпал (нет завершающего `/`, каталог через симлинк); попробуйте абсолютный путь, например `gitdir:/home/<SERVER_USER>/workspace/work/` |
| E-mail верный, ключ/аккаунт не тот | Нет `sshCommand` или remote использует алиас/хост, который его переопределяет |
| Нужны пути без учёта регистра | Используйте `gitdir/i:` вместо `gitdir:` |
| Репозиторий вне обоих каталогов | Задайте локально: `git config user.email <GIT_PERSONAL_EMAIL>` |
| В старых коммитах неверный e-mail | Идентичность применяется в момент коммита; Git перечитывает конфиги при каждой команде, перезапуск не нужен |

Next: [IDE по SSH](ide-remote-ssh.md)
