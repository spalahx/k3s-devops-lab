# Установка K3s

Устанавливает K3s (облегчённый дистрибутив Kubernetes в одном бинарнике) как systemd-сервис со встроенным ingress-контроллером Traefik и настраивает `kubectl` для обычного пользователя. K3s включает собственные containerd, CoreDNS, Traefik и балансировщик сервисов, поэтому для одного узла больше ничего не нужно.

## 1. Установка

```bash
curl -sfL https://get.k3s.io | sh -
```

Скрипт определяет архитектуру CPU, ставит `/usr/local/bin/k3s`, создаёт симлинк `kubectl`, systemd-юнит `k3s` и запускает его. Занимает от 30 секунд до нескольких минут.

Полезные опции установщика (переменные окружения или флаги после `sh -s -`):

| Опция | Эффект |
|---|---|
| `INSTALL_K3S_EXEC="--write-kubeconfig-mode 644"` | Делает `/etc/rancher/k3s/k3s.yaml` читаемым всем, чтобы `kubectl` работал без `sudo` (допустимо на машине с одним пользователем; иначе используйте шаг 3) |
| `INSTALL_K3S_EXEC="--disable traefik"` | Не разворачивать Traefik (только если ставите другой ingress-контроллер). По умолчанию Traefik остаётся; следующие страницы на него рассчитаны |
| `INSTALL_K3S_VERSION=v1.30.4+k3s1` | Зафиксировать версию вместо канала stable |

Пример с опцией:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
```

## 2. Проверка узла

```bash
sudo k3s kubectl get node
```

`STATUS` должен быть `Ready` (если `NotReady`, подождите 20–30 секунд). Системные поды стабилизируются за пару минут:

```bash
sudo k3s kubectl get pods -A
```

## 3. kubectl для обычного пользователя

Скопируйте сгенерированный kubeconfig (содержит учётные данные кластера) в домашний каталог:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config
```

Скопированный файл указывает на `https://127.0.0.1:6443`, что верно, когда `kubectl` запускается на самом сервере. Чтобы работать с ноутбука, скопируйте файл туда и замените `127.0.0.1` на `<SERVER_IP>` (порт 6443 должен быть доступен; см. страницы про firewall и удалённый доступ).

> **Warning:** файл — это снимок. После переустановки K3s сертификаты меняются, и копия перестаёт работать; скопируйте её заново.

## Проверка

```bash
kubectl get node
kubectl get pods -A
kubectl -n kube-system get svc traefik
```

Ожидается: узел `Ready`, поды `coredns`, `traefik`, `local-path-provisioner`, `metrics-server` в `Running`, сервис `traefik` типа `LoadBalancer` с внешним IP `<SERVER_IP>`.

| Симптом | Решение |
|---|---|
| `permission denied` на `/etc/rancher/k3s/k3s.yaml` | `kubectl` читает файл по умолчанию, доступный только root; выполните шаг 3 и проверьте `echo $KUBECONFIG` |
| `connection refused` | `sudo systemctl status k3s`; перезапуск `sudo systemctl restart k3s`; логи: `sudo journalctl -u k3s -f` |
| Узел `NotReady` несколько минут | Мало RAM/диска или конфликт портов 80/443/6443; смотрите journal |
| Поды не находят образы, собранные в Docker | K3s использует свой containerd; импорт: `docker save <image> \| sudo k3s ctr images import -` |

## Остановка и удаление

```bash
sudo systemctl stop k3s              # остановить кластер (данные сохраняются)
sudo /usr/local/bin/k3s-killall.sh   # дополнительно убить все процессы подов
sudo /usr/local/bin/k3s-uninstall.sh # удалить K3s и все данные кластера
```

> **Warning:** `k3s-uninstall.sh` удаляет состояние кластера. Данные в каталогах `hostPath` вне `/var/lib/rancher/k3s` не затрагиваются.

Next: [Ingress через Traefik и первое приложение](ingress-traefik-first-app.md)
