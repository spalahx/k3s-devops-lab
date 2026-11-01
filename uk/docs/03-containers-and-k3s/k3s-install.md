# Встановлення K3s

Встановлює K3s (легкий дистрибутив Kubernetes в одному бінарному файлі) як службу systemd зі вбудованим ingress-контролером Traefik і налаштовує `kubectl` для звичайного користувача. K3s постачається зі своїми containerd, CoreDNS, Traefik і балансувальником навантаження для сервісів, тож на одному вузлі більше нічого не потрібно.

## 1. Встановлення

```bash
curl -sfL https://get.k3s.io | sh -
```

Скрипт визначає архітектуру процесора, встановлює `/usr/local/bin/k3s`, створює символічне посилання `kubectl`, створює юніт systemd `k3s` і запускає його. Триває від 30 секунд до кількох хвилин.

Корисні опції інсталятора (змінні середовища або прапорці після `sh -s -`):

| Опція | Дія |
|---|---|
| `INSTALL_K3S_EXEC="--write-kubeconfig-mode 644"` | Робить `/etc/rancher/k3s/k3s.yaml` доступним для читання всім, щоб `kubectl` працював без `sudo` (прийнятно на машині з одним користувачем; інакше скористайтеся кроком 3) |
| `INSTALL_K3S_EXEC="--disable traefik"` | Не розгортати Traefik (лише якщо використовуєте інший ingress-контролер). Типове встановлення його залишає; наступні сторінки на нього спираються |
| `INSTALL_K3S_VERSION=v1.36.4+k3s1` | Зафіксувати конкретну версію замість стабільного каналу (версія еталонного сервера; перед встановленням перевірте актуальний stable-реліз) |

Приклад з опцією:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
```

## 2. Перевірте вузол

```bash
sudo k3s kubectl get node
```

`STATUS` має бути `Ready` (зачекайте 20–30 секунд, якщо `NotReady`). Системним подам потрібно кілька хвилин, щоб стабілізуватися:

```bash
sudo k3s kubectl get pods -A
```

## 3. kubectl для звичайного користувача

Скопіюйте згенерований kubeconfig (містить облікові дані кластера) у домашній каталог користувача:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config
```

Скопійований файл вказує на `https://127.0.0.1:6443`, що правильно, коли `kubectl` запускається на сервері. Щоб користуватися `kubectl` з ноутбука, скопіюйте файл туди й замініть `127.0.0.1` на `<SERVER_IP>` (порт 6443 має бути доступним; див. сторінки про брандмауер і віддалений доступ).

> **Попередження:** файл є знімком. Якщо K3s перевстановити, сертифікати зміняться, і копія перестане працювати; скопіюйте її знову.

## Перевірка

```bash
kubectl get node
kubectl get pods -A
kubectl -n kube-system get svc traefik
```

Очікується: вузол `Ready`, поди `coredns`, `traefik`, `local-path-provisioner`, `metrics-server` у стані `Running`, а сервіс `traefik` типу `LoadBalancer` має `<SERVER_IP>` як зовнішню IP-адресу.

| Симптом | Рішення |
|---|---|
| `permission denied` на `/etc/rancher/k3s/k3s.yaml` | `kubectl` читає типовий файл, доступний лише root; виконайте крок 3 і перевірте `echo $KUBECONFIG` |
| `connection refused` | `sudo systemctl status k3s`; перезапустіть через `sudo systemctl restart k3s`; журнали: `sudo journalctl -u k3s -f` |
| Вузол `NotReady` кілька хвилин | Мало RAM/диска або конфлікт портів 80/443/6443; перегляньте журнал |
| Образи, зібрані в Docker, не знаходяться подами | K3s використовує власний containerd; імпорт: `docker save <image> \| sudo k3s ctr images import -` |

## Зупинка та видалення

```bash
sudo systemctl stop k3s              # зупинити кластер (дані зберігаються)
sudo /usr/local/bin/k3s-killall.sh   # також завершити всі процеси подів
sudo /usr/local/bin/k3s-uninstall.sh # видалити K3s і всі дані кластера
```

> **Попередження:** `k3s-uninstall.sh` видаляє стан кластера. Дані в каталогах `hostPath` поза `/var/lib/rancher/k3s` не зачіпаються.

Далі: [Ingress з Traefik і перший застосунок](ingress-traefik-first-app.md)
