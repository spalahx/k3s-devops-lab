# IDE через SSH і код у подах

Налаштовує структуру робочого простору на сервері, підключає VS Code або PhpStorm до нього через SSH, щоб файли редагувалися на місці, і монтує каталог проєкту в под через `hostPath`, щоб зміни коду були видимі миттєво без перезбирання образу. Призначено для розробки; продакшн-образи мають містити свій код.

## 1. Структура робочого простору на сервері

```
~/workspace/
    work/<PROJECT_NAME>/       source code, Git repository (work identity)
    personal/<PROJECT_NAME>/   source code, Git repository (personal identity)
~/k8s-infrastructure/
    projects/<PROJECT_NAME>/   Kubernetes manifests only (no source code)
```

Код і маніфести тримають окремо, щоб маніфести можна було версіонувати й застосовувати незалежно від будь-якого репозиторію застосунку. Ідентичності за каталогами: [кілька ідентичностей Git](multiple-git-identities.md).

## 2. SSH-запис на ноутбуці

`~/.ssh/config` на ноутбуці (macOS або Linux); обидві IDE можуть його повторно використати:

```
Host <SERVER_HOSTNAME>
    HostName <SERVER_IP>
    Port <SSH_PORT>
    User <SERVER_USER>
    IdentityFile ~/.ssh/id_ed25519
```

Тут ключ — це той, яким ви входите на сервер (його `.pub` лежить у `~/.ssh/authorized_keys` сервера), а не ключ Git. Перевірка: `ssh <SERVER_HOSTNAME>`.

## 3a. VS Code (Remote - SSH)

1. Встановіть розширення "Remote - SSH".
2. Command Palette > `Remote-SSH: Connect to Host...` > `<SERVER_HOSTNAME>`.
3. `File > Open Folder` > `/home/<SERVER_USER>/workspace/work/<PROJECT_NAME>`.

VS Code встановлює невеликий серверний компонент у `~/.vscode-server` при першому підключенні; розширення, що працюють з файлами (PHP, YAML, Git), після цього виконуються на сервері.

## 3b. PhpStorm

| Режим | Як |
|---|---|
| Remote Development (рекомендовано) | Welcome screen > Remote Development > SSH > New Connection (хост `<SERVER_IP>`, порт `<SSH_PORT>`, користувач `<SERVER_USER>`, файл ключа) > виберіть версію IDE та каталог проєкту. На сервері працює headless-бекенд IDE (потрібно кілька ГБ RAM); на ноутбуці працює лише інтерфейс |
| Deployment (синхронізація SFTP) | `Settings > Build, Execution, Deployment > Deployment` > додайте SFTP-сервер з тими самими обліковими даними; Mappings: локальний каталог проєкту до `/home/<SERVER_USER>/workspace/work/<PROJECT_NAME>`; увімкніть автоматичне завантаження при збереженні. Код редагується локально й дзеркалиться на сервер |

Використовуйте режим Remote Development, коли сервер має ресурси; на слабкій машині використовуйте Deployment.

## 4. Змонтуйте код у под (`hostPath`)

У маніфесті Deployment проєкту:

```yaml
      containers:
      - name: app
        image: <APP_IMAGE>
        volumeMounts:
        - name: app-code
          mountPath: /var/www/html
      volumes:
      - name: app-code
        hostPath:
          path: /home/<SERVER_USER>/workspace/work/<PROJECT_NAME>
          type: Directory
```

- `hostPath` монтує каталог диска вузла в контейнер, тож збереження файлу в IDE одразу змінює запущений застосунок.
- `path` має бути абсолютним; `~` не розгортається. `type: Directory` призводить до того, що под не запуститься, якщо каталогу немає (спершу клонуйте репозиторій).
- Діє лише на одновузловому кластері; з кількома вузлами под може потрапити туди, де цього каталогу немає.

```bash
kubectl apply -f deployment.yaml
```

## 5. Права доступу до файлів

Процес у контейнері працює від власного користувача (для PHP-FPM: `www-data`, UID 82 в образах Alpine, UID 33 в образах на базі Debian), а не від `<SERVER_USER>`. Каталоги, у які пише застосунок (для WordPress `wp-content`, особливо `uploads`), мають бути доступні йому для запису:

```bash
cd ~/workspace/work/<PROJECT_NAME>
sudo chown -R <SERVER_USER>:<SERVER_USER> .
sudo find wp-content/ -type d -exec chmod 775 {} +
sudo find wp-content/ -type f -exec chmod 664 {} +
git config core.fileMode false
```

- `775`/`664` дають власнику та групі читання/запис; користувач пода має бути власником або входити в групу. Якщо UID не збігається, або виконайте `chown` для каталогів із записом на цей UID (`sudo chown -R 82:82 wp-content/uploads`), або, для тимчасового налаштування, використайте `777`/`666`.
- `core.fileMode false` не дає Git повідомляти про зміни прав як про модифікації; воно зберігається в `.git/config` цього клону, тож повторюйте його після кожного нового клонування.
- Права втрачаються після деяких операцій (`git pull`, що створює файли, розпакування архіву): застосуйте команди знову.

## Перевірка

IDE: відкрийте вбудований термінал і виконайте `hostname; pwd`; має вивестися ім'я сервера та шлях `/home/<SERVER_USER>/workspace/...`.

Под:

```bash
kubectl get pods
kubectl exec -it <pod> -- ls /var/www/html     # same files as in ~/workspace/...
kubectl exec -it <pod> -- touch /var/www/html/wp-content/uploads/_t && echo writable
```

Відредагуйте файл в IDE та перезавантажте сторінку: зміна діє одразу без перезапуску пода.

| Симптом | Рішення |
|---|---|
| IDE не може підключитися | Порт відрізняється від `<SSH_PORT>`; ключа ноутбука немає в `authorized_keys`; спершу перевірте звичайним `ssh` |
| Под `CreateContainerError` / завис у `ContainerCreating` | Каталогу `hostPath` немає або шлях відносний; `kubectl describe pod <pod>` |
| Застосунок пише "Permission denied" / "Unable to create directory" | Крок 5 |
| Git показує кожен файл зміненим після chmod | `git config core.fileMode false` |
| Бекенд Remote Development повільний або його вбито | Недостатньо RAM на сервері; перейдіть на режим Deployment (SFTP) |

Далі: [Угоди щодо структури K8s](../05-deploying-projects/k8s-structure-conventions.md)
