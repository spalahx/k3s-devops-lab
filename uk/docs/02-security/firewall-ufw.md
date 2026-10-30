# Брандмауер (UFW)

Блокує весь вхідний трафік, окрім SSH і веб-портів, за допомогою UFW (Uncomplicated Firewall, надбудова над iptables/nftables). Налаштуйте його до зміни порту SSH і до встановлення K3s, оскільки K3s додає власні правила, а деякі комбінації ламають мережу Pod.

> **Попередження:** `ufw enable` без правила для SSH обриває вашу сесію. Спершу додайте правило SSH і тримайте другу сесію відкритою.

## 1. Типові політики

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

## 2. Дозвіл SSH (до ввімкнення)

Використовуйте порт, який sshd слухає зараз. Під час міграції порту дозвольте обидва:

```bash
sudo ufw allow 22/tcp comment 'SSH (temporary)'
sudo ufw allow <SSH_PORT>/tcp comment 'SSH'
```

Опційно, SSH лише з LAN (адаптуйте підмережу; це суворіше і безпечно для домашнього сервера):

```bash
sudo ufw allow from 192.168.1.0/24 to any port <SSH_PORT> proto tcp comment 'SSH from LAN'
```

Для сервера з публічною IP-адресою обмежуйте SSH відомими адресами, де це можливо, наприклад `sudo ufw allow from 203.0.113.10 to any port <SSH_PORT> proto tcp`.

## 3. Веб-порти

Traefik (ingress-контролер K3s) обслуговує HTTP/HTTPS на вузлі:

```bash
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
```

Варіант лише для LAN, для домашнього сервера, який не має бути досяжним ззовні підмережі:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 80 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 443 proto tcp
```

## 4. Правила K3s

На одновузловому кластері ззовні потрібні лише 80/443. Проте Pod і сервіси спілкуються через власні інтерфейси вузла (`cni0`, `flannel.1`), а типова політика UFW відкидає цей трафік. Явно дозвольте мережі Pod і сервісів K3s (типові CIDR):

```bash
sudo ufw allow from 10.42.0.0/16 to any comment 'K3s pods'
sudo ufw allow from 10.43.0.0/16 to any comment 'K3s services'
```

Лише якщо ви використовуєте Kubernetes API або kubectl з іншої машини, або додаєте більше вузлів:

| Порт | Протокол | Призначення | Відкрити для |
|---|---|---|---|
| 6443 | tcp | Kubernetes API | лише ноутбук / agent-вузли |
| 10250 | tcp | метрики kubelet | лише інші вузли |
| 8472 | udp | flannel VXLAN | лише інші вузли |

```bash
sudo ufw allow from 192.168.1.0/24 to any port 6443 proto tcp comment 'K3s API from LAN'
```

## 5. Ввімкнення та перевірка

```bash
sudo ufw enable
sudo ufw status numbered
sudo ufw status verbose
```

Очікується: `Status: active`, `Default: deny (incoming), allow (outgoing)`, правила для `<SSH_PORT>`, 80, 443. Коли міграцію порту SSH завершено, видаліть правило для порту 22:

```bash
sudo ufw status numbered
sudo ufw delete allow 22/tcp
```

Видаляйте за текстом правила або за номером із `status numbered` (номери зміщуються після кожного видалення).

## Підводні камені

- **Docker обходить UFW.** Порти, опубліковані через `docker run -p 8080:80`, вставляються в iptables перед UFW, тому `ufw deny` їх не приховує. Прив'яжіть до localhost (`-p 127.0.0.1:8080:80`) або не публікуйте порт.
- **K3s додає власні правила iptables** (service load balancer для Traefik, NAT kube-proxy). Порти 80/443 досягають Traefik через DNAT у forward-шляху; якщо після ввімкнення UFW сайти видають timeout, а `curl localhost` на сервері працює, перевірте `sudo ufw status` на наявність наведених вище правил для CIDR Pod/сервісів і, за потреби, задайте `DEFAULT_FORWARD_POLICY="ACCEPT"` у `/etc/default/ufw`, потім `sudo ufw reload`.
- **Pod не можуть розв'язувати DNS / досягати інтернету після `ufw enable`:** немає наведеного вище правила для CIDR Pod. Швидка перевірка: `kubectl run -it --rm t --image=busybox --restart=Never -- nslookup kubernetes.default`.
- **Порядок має значення:** `ufw allow` перед `ufw enable`, а правило для порту SSH перед зміною порту SSH.
- **Інші сервіси потребують власних правил:** наприклад, `sudo ufw allow samba` ([Samba](../09-optional-extras/samba-file-storage.md)), з обмеженням підмережею LAN.
- Якщо K3s усе ще працює некоректно, а машина доступна лише з довіреної LAN, запасний варіант із документації K3s це вимкнути UFW (`sudo ufw disable`) і покладатися на брандмауер роутера. На будь-якому сервері з публічною IP-адресою віддавайте перевагу наведеним вище правилам.

## Перевірка

```bash
sudo ufw status verbose
sudo ss -tlnp | grep -E ":<SSH_PORT>|:80 |:443 "
```

З ноутбука: `ssh <SERVER_HOSTNAME>` працює; `nc -zv <SERVER_IP> 3306` (закритий порт) завершується timeout. Після встановлення K3s `kubectl get pods -A` має показувати всі Pod у стані `Running`.

Далі: [Fail2ban](fail2ban.md)
