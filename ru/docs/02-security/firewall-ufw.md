# Фаервол (UFW)

Блокирует весь входящий трафик, кроме SSH и веб-портов, с помощью UFW (Uncomplicated Firewall, надстройка над iptables/nftables). Настройте его до смены порта SSH и до установки K3s: K3s добавляет собственные правила, и некоторые сочетания ломают сеть подов.

> **Warning:** `ufw enable` без правила для SSH оборвёт вашу сессию. Сначала добавьте правило для SSH и держите вторую сессию открытой.

## 1. Политики по умолчанию

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

## 2. Разрешить SSH (до включения)

Используйте порт, который sshd слушает сейчас. На время миграции порта разрешите оба:

```bash
sudo ufw allow 22/tcp comment 'SSH (temporary)'
sudo ufw allow <SSH_PORT>/tcp comment 'SSH'
```

Необязательно, SSH только из LAN (подставьте свою подсеть; строже и безопасно для домашнего сервера):

```bash
sudo ufw allow from 192.168.1.0/24 to any port <SSH_PORT> proto tcp comment 'SSH from LAN'
```

Для сервера с публичным IP по возможности ограничьте SSH известными адресами, например `sudo ufw allow from 203.0.113.10 to any port <SSH_PORT> proto tcp`.

## 3. Веб-порты

Traefik (ingress-контроллер K3s) обслуживает HTTP/HTTPS на узле:

```bash
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
```

Вариант только для LAN, если домашний сервер не должен быть доступен снаружи подсети:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 80 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 443 proto tcp
```

## 4. Правила для K3s

На одноузловом кластере снаружи нужны только 80/443. Но поды и сервисы общаются через интерфейсы самого узла (`cni0`, `flannel.1`), и политика UFW по умолчанию этот трафик отбрасывает. Явно разрешите сети подов и сервисов K3s (CIDR по умолчанию):

```bash
sudo ufw allow from 10.42.0.0/16 to any comment 'K3s pods'
sudo ufw allow from 10.43.0.0/16 to any comment 'K3s services'
```

Только если используете Kubernetes API или kubectl с другой машины, либо добавляете узлы:

| Порт | Протокол | Назначение | Открывать для |
|---|---|---|---|
| 6443 | tcp | Kubernetes API | только ноутбук / agent-узлы |
| 10250 | tcp | метрики kubelet | только другие узлы |
| 8472 | udp | flannel VXLAN | только другие узлы |

```bash
sudo ufw allow from 192.168.1.0/24 to any port 6443 proto tcp comment 'K3s API from LAN'
```

## 5. Включение и проверка

```bash
sudo ufw enable
sudo ufw status numbered
sudo ufw status verbose
```

Ожидается: `Status: active`, `Default: deny (incoming), allow (outgoing)`, правила для `<SSH_PORT>`, 80, 443. Когда миграция порта SSH завершена, удалите правило для порта 22:

```bash
sudo ufw status numbered
sudo ufw delete allow 22/tcp
```

Удаляйте по тексту правила или по номеру из `status numbered` (номера сдвигаются после каждого удаления).

## Подводные камни

- **Docker обходит UFW.** Порты, опубликованные через `docker run -p 8080:80`, вставляются в iptables раньше UFW, поэтому `ufw deny` их не скрывает. Привязывайте к localhost (`-p 127.0.0.1:8080:80`) или не публикуйте порт.
- **K3s добавляет свои правила iptables** (service load balancer для Traefik, NAT kube-proxy). Порты 80/443 доходят до Traefik через DNAT в цепочке forward; если после включения UFW сайты не открываются по таймауту, а `curl localhost` на сервере работает, проверьте правила для CIDR подов/сервисов выше и при необходимости задайте `DEFAULT_FORWARD_POLICY="ACCEPT"` в `/etc/default/ufw`, затем `sudo ufw reload`.
- **Поды не резолвят DNS / нет интернета после `ufw enable`:** отсутствует правило для CIDR подов. Быстрый тест: `kubectl run -it --rm t --image=busybox --restart=Never -- nslookup kubernetes.default`.
- **Порядок важен:** `ufw allow` до `ufw enable`, правило для порта SSH до смены порта SSH.
- **Другим сервисам нужны свои правила:** например `sudo ufw allow samba` ([Samba](../09-optional-extras/samba-file-storage.md)), ограничьте подсетью LAN.
- Если K3s всё равно ведёт себя странно, а машина доступна только из доверенной LAN, запасной вариант из документации K3s — отключить UFW (`sudo ufw disable`) и полагаться на фаервол роутера. На любом сервере с публичным IP используйте правила выше.

## Verify

```bash
sudo ufw status verbose
sudo ss -tlnp | grep -E ":<SSH_PORT>|:80 |:443 "
```

С ноутбука: `ssh <SERVER_HOSTNAME>` работает; `nc -zv <SERVER_IP> 3306` (закрытый порт) завершается по таймауту. После установки K3s `kubectl get pods -A` должен показывать все поды `Running`.

Next: [Fail2ban](fail2ban.md)
