# Кілька ідентичностей Git

Змушує Git автоматично вибирати правильну електронну пошту та SSH-ключ за каталогом, у якому лежить репозиторій: усе під `~/workspace/work/` комітиться як робоча ідентичність, усе під `~/workspace/personal/` — як особиста. Використовує умовні включення Git (`includeIf`). Пропустіть, якщо ідентичність одна.

Потребує ключів зі сторінки [SSH-ключі для Git](ssh-keys-for-git.md).

## 1. Структура каталогів

```bash
mkdir -p ~/workspace/work ~/workspace/personal
```

Клонуйте репозиторії у відповідний каталог; розташування визначає ідентичність. Вихідний код лежить у `~/workspace/`, маніфести Kubernetes — в окремому `~/k8s-infrastructure/`.

## 2. Глобальний `~/.gitconfig`

```ini
[user]
    name = <GIT_USER_NAME>

[includeIf "gitdir:~/workspace/work/"]
    path = ~/.gitconfig-work

[includeIf "gitdir:~/workspace/personal/"]
    path = ~/.gitconfig-personal
```

`<GIT_USER_NAME>` — ім'я, що відображається в комітах. `includeIf "gitdir:..."` читає додатковий файл лише тоді, коли `.git` репозиторію розташований усередині цього шляху. Кінцевий `/` обов'язковий: він відповідає каталогу та всьому, що нижче.

## 3. Файли ідентичностей

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

- `core.sshCommand` вказує Git, який приватний ключ використовувати для fetch/push. `IdentitiesOnly=yes` не дає ssh пропонувати ще й ключі з агента або типові (які можуть автентифікувати вас як не той обліковий запис).
- За цієї схеми віддалені репозиторії зберігають справжній хост (`git@github.com:<ORG>/<REPO>.git`); Host-аліаси з попередньої сторінки для цих репозиторіїв не потрібні.
- Файли ідентичностей лежать у домашньому каталозі, поза репозиторіями, тож ніколи не потрапляють у репозиторій.

## Перевірка

```bash
cd ~/workspace/work
git clone git@github.com:<ORG>/<REPO>.git && cd <REPO>
git config user.email                       # <GIT_WORK_EMAIL>
git config --show-origin --get-all user.email
git config core.sshCommand

cd ~/workspace/personal/<OTHER_REPO>
git config user.email                       # <GIT_PERSONAL_EMAIL>
```

`--show-origin` виводить, який файл надав значення.

| Симптом | Рішення |
|---|---|
| Порожній `user.email` | Не всередині репозиторію, або шлях в `includeIf` не збігається (бракує кінцевого `/`, каталог є символічним посиланням); спробуйте абсолютний шлях, наприклад `gitdir:/home/<SERVER_USER>/workspace/work/` |
| Правильна пошта, хибний ключ/обліковий запис | Бракує `sshCommand`, або віддалений репозиторій використовує аліас/хост, який його перевизначає |
| Потрібні шляхи без урахування регістру | Використовуйте `gitdir/i:` замість `gitdir:` |
| Репозиторій поза обома каталогами | Задайте локально: `git config user.email <GIT_PERSONAL_EMAIL>` |
| Старі коміти мають хибну пошту | Ідентичність застосовується в момент коміту; Git читає конфігурації при кожній команді, перезапуск не потрібен |

Далі: [IDE через SSH](ide-remote-ssh.md)
