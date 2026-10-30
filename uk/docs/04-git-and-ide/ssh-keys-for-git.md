# SSH-ключі для Git

Створює на сервері окремі SSH-ключі ed25519 для GitLab/GitHub, підключає їх через Host-аліаси в `~/.ssh/config` і перевіряє доступ за допомогою `ssh -T`. Ключі для Git-провайдера відокремлені від ключа, яким ви входите на сам сервер (той лежить на ноутбуці, а його публічна частина — в `authorized_keys` сервера).

Створюються два ключі, щоб робочий і особистий облікові записи залишалися ізольованими (провайдер не приймає той самий ключ у двох облікових записах). З одним обліковим записом створіть один ключ і пропустіть другий.

## 1. Згенеруйте ключі

```bash
ssh-keygen -t ed25519 -C "<GIT_WORK_EMAIL>" -f ~/.ssh/id_ed25519_work
ssh-keygen -t ed25519 -C "<GIT_PERSONAL_EMAIL>" -f ~/.ssh/id_ed25519_personal
```

| Прапорець | Значення |
|---|---|
| `-t ed25519` | Сучасний, короткий, швидкий тип ключа |
| `-C` | Коментар, що відображається в списку ключів провайдера |
| `-f` | Вихідний файл; завжди давайте різні імена, інакше другий ключ перезапише перший |

Парольна фраза необов'язкова; порожня зручна, але означає, що будь-хто, хто прочитає файл, може користуватися ключем. З парольною фразою завантажуйте ключ в агент на кожен сеанс: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519_work`.

Результат у `~/.ssh/`: `id_ed25519_work` та `id_ed25519_personal` (приватні, нікому не передавайте) плюс файли `.pub` (публічні).

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519_work ~/.ssh/id_ed25519_personal
```

## 2. Host-аліаси в `~/.ssh/config`

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

- `IdentitiesOnly yes` змушує ssh пропонувати лише вказаний ключ; без цього спершу можуть бути спробувані ключі з агента або типові, і провайдер автентифікує вас як не той обліковий запис.
- Для GitLab використовуйте такий самий блок з `HostName gitlab.com` (або ім'ям вашого власного хоста, плюс `Port <SSH_PORT>`, якщо порт не 22). Залишайте лише ті хости, якими користуєтеся.
- Тоді віддалені репозиторії використовують аліас замість справжнього хоста:

```bash
git clone git@github-work:<ORG>/<REPO>.git
git remote set-url origin git@github-personal:<USER>/<REPO>.git
```

```bash
chmod 600 ~/.ssh/config
```

> **Примітка:** [Кілька ідентичностей Git](multiple-git-identities.md) показує альтернативу, яка вибирає ключ за каталогом через `core.sshCommand`; там віддалені репозиторії зберігають справжнє ім'я хоста й аліаси не потрібні. Використовуйте одну схему на репозиторій.

## 3. Додайте публічні ключі до облікових записів

```bash
cat ~/.ssh/id_ed25519_work.pub
cat ~/.ssh/id_ed25519_personal.pub
```

Скопіюйте кожен одним рядком (починається з `ssh-ed25519`, без переносів рядків) у відповідний обліковий запис:

| Провайдер | Розташування |
|---|---|
| GitHub | Settings > SSH and GPG keys > New SSH key |
| GitLab | Preferences > SSH Keys |

## Перевірка

```bash
ssh -T git@github-work
ssh -T git@github-personal
```

Очікується: GitHub `Hi <user>! You've successfully authenticated, but GitHub does not provide shell access.`; GitLab виводить `Welcome to GitLab, @<user>!`. Налагодження: `ssh -vT git@github-work`.

| Симптом | Рішення |
|---|---|
| `Permission denied (publickey)` | Ключ не додано до облікового запису, не той обліковий запис, або вставлений ключ розбито на кілька рядків |
| Автентифікація як не той користувач | Бракує `IdentitiesOnly yes`, або віддалений репозиторій досі використовує `git@github.com:` замість аліаса |
| `Bad owner or permissions` | `chmod 600` для приватних ключів і config, `chmod 700 ~/.ssh` |
| `Could not resolve hostname github-work` | Помилка в аліасі або `~/.ssh/config` не в домашньому каталозі користувача сервера |

Далі: [Кілька ідентичностей Git](multiple-git-identities.md)
