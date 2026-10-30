# IDE по SSH и код в Pod

Настраивает структуру рабочих каталогов на сервере, подключает VS Code или PhpStorm по SSH, чтобы файлы редактировались на месте, и монтирует каталог проекта в Pod через `hostPath`, чтобы изменения кода были видны сразу без пересборки образа. Предназначено для разработки; в production код должен находиться в образе.

## 1. Структура workspace на сервере

```
~/workspace/
    work/<PROJECT_NAME>/       исходный код, Git-репозиторий (рабочая идентичность)
    personal/<PROJECT_NAME>/   исходный код, Git-репозиторий (личная идентичность)
~/k8s-infrastructure/
    projects/<PROJECT_NAME>/   только манифесты Kubernetes (без исходного кода)
```

Код и манифесты разделены, чтобы манифесты можно было версионировать и применять независимо от репозитория приложения. Идентичности по каталогам: [несколько Git-идентичностей](multiple-git-identities.md).

## 2. SSH-запись на ноутбуке

`~/.ssh/config` на ноутбуке (macOS или Linux); обе IDE могут его использовать:

```
Host <SERVER_HOSTNAME>
    HostName <SERVER_IP>
    Port <SSH_PORT>
    User <SERVER_USER>
    IdentityFile ~/.ssh/id_ed25519
```

Здесь ключ для входа на сервер (его `.pub` лежит в `~/.ssh/authorized_keys` сервера), а не ключ Git. Проверка: `ssh <SERVER_HOSTNAME>`.

## 3a. VS Code (Remote - SSH)

1. Установите расширение "Remote - SSH".
2. Command Palette > `Remote-SSH: Connect to Host...` > `<SERVER_HOSTNAME>`.
3. `File > Open Folder` > `/home/<SERVER_USER>/workspace/work/<PROJECT_NAME>`.

При первом подключении VS Code ставит небольшой серверный компонент в `~/.vscode-server`; расширения, работающие с файлами (PHP, YAML, Git), затем выполняются на сервере.

## 3b. PhpStorm

| Режим | Как |
|---|---|
| Remote Development (рекомендуется) | Welcome screen > Remote Development > SSH > New Connection (host `<SERVER_IP>`, port `<SSH_PORT>`, user `<SERVER_USER>`, файл ключа) > выбрать версию IDE и каталог проекта. На сервере запускается headless-бэкенд IDE (нужно несколько ГБ RAM); на ноутбуке работает только интерфейс |
| Deployment (синхронизация по SFTP) | `Settings > Build, Execution, Deployment > Deployment` > добавить SFTP-сервер с теми же данными; Mappings: локальный каталог проекта в `/home/<SERVER_USER>/workspace/work/<PROJECT_NAME>`; включить автоматическую загрузку при сохранении. Код редактируется локально и зеркалируется на сервер |

Remote Development используйте, если у сервера хватает ресурсов; на слабой машине выбирайте Deployment.

## 4. Монтирование кода в Pod (`hostPath`)

В манифесте Deployment проекта:

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

- `hostPath` монтирует каталог диска узла в контейнер, поэтому сохранение файла в IDE сразу меняет работающее приложение.
- `path` должен быть абсолютным; `~` не раскрывается. `type: Directory` приводит к ошибке старта Pod, если каталога нет (сначала клонируйте репозиторий).
- Работает только на одноузловом кластере; при нескольких узлах Pod может попасть туда, где каталога нет.

```bash
kubectl apply -f deployment.yaml
```

## 5. Права на файлы

Процесс в контейнере работает от собственного пользователя (для PHP-FPM: `www-data`, UID 82 в образах Alpine, UID 33 в образах на Debian), а не от `<SERVER_USER>`. Каталоги, в которые пишет приложение (для WordPress `wp-content`, особенно `uploads`), должны быть ему доступны на запись:

```bash
cd ~/workspace/work/<PROJECT_NAME>
sudo chown -R <SERVER_USER>:<SERVER_USER> .
sudo find wp-content/ -type d -exec chmod 775 {} +
sudo find wp-content/ -type f -exec chmod 664 {} +
git config core.fileMode false
```

- `775`/`664` дают владельцу и группе чтение/запись; пользователь Pod должен быть владельцем или входить в группу. Если UID не совпадает, либо сделайте `chown` записываемых каталогов на этот UID (`sudo chown -R 82:82 wp-content/uploads`), либо для временной конфигурации используйте `777`/`666`.
- `core.fileMode false` перестаёт показывать изменения прав как модификации; хранится в `.git/config` конкретного клона, поэтому повторяйте после каждого нового клонирования.
- Права теряются после некоторых операций (`git pull`, создающий файлы, распаковка архива): повторите команды.

## Проверка

IDE: откройте встроенный терминал и выполните `hostname; pwd`; должны быть имя сервера и путь `/home/<SERVER_USER>/workspace/...`.

Pod:

```bash
kubectl get pods
kubectl exec -it <pod> -- ls /var/www/html     # те же файлы, что в ~/workspace/...
kubectl exec -it <pod> -- touch /var/www/html/wp-content/uploads/_t && echo writable
```

Измените файл в IDE и обновите страницу: изменение видно без перезапуска Pod.

| Симптом | Решение |
|---|---|
| IDE не подключается | Порт отличается от `<SSH_PORT>`; ключа ноутбука нет в `authorized_keys`; сначала проверьте обычным `ssh` |
| Pod `CreateContainerError` / завис в `ContainerCreating` | Нет каталога `hostPath` или путь относительный; `kubectl describe pod <pod>` |
| Приложение: "Permission denied" / "Unable to create directory" | Шаг 5 |
| Git показывает все файлы изменёнными после chmod | `git config core.fileMode false` |
| Бэкенд Remote Development тормозит или убивается | Мало RAM на сервере; переключитесь на Deployment (SFTP) |

Next: [Конвенции структуры K8s](../05-deploying-projects/k8s-structure-conventions.md)
