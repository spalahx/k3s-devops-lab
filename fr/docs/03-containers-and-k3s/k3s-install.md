# Installation de K3s

Installe K3s (une distribution Kubernetes légère, en un seul binaire) comme service systemd avec le contrôleur Ingress Traefik fourni, et configure `kubectl` pour l'utilisateur standard. K3s embarque son propre containerd, CoreDNS, Traefik et un répartiteur de charge de services ; rien d'autre n'est donc nécessaire sur un nœud unique.

## 1. Installation

```bash
curl -sfL https://get.k3s.io | sh -
```

Le script détecte l'architecture du processeur, installe `/usr/local/bin/k3s`, crée le lien symbolique `kubectl`, crée l'unité systemd `k3s` et la démarre. Compter de 30 secondes à quelques minutes.

Options utiles de l'installateur (variables d'environnement ou options après `sh -s -`) :

| Option | Effet |
|---|---|
| `INSTALL_K3S_EXEC="--write-kubeconfig-mode 644"` | Rend `/etc/rancher/k3s/k3s.yaml` lisible par tous pour que `kubectl` fonctionne sans `sudo` (acceptable sur une machine mono-utilisateur ; sinon utilisez l'étape 3) |
| `INSTALL_K3S_EXEC="--disable traefik"` | Ne déploie pas Traefik (uniquement si vous apportez un autre contrôleur Ingress). L'installation par défaut le conserve ; les pages suivantes en dépendent |
| `INSTALL_K3S_VERSION=v1.30.4+k3s1` | Fixe une version précise au lieu du canal stable |

Exemple avec une option :

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
```

## 2. Vérifier le nœud

```bash
sudo k3s kubectl get node
```

`STATUS` doit être `Ready` (attendez 20 à 30 secondes si `NotReady`). Les pods système mettent quelques minutes à se stabiliser :

```bash
sudo k3s kubectl get pods -A
```

## 3. kubectl pour l'utilisateur standard

Copiez le kubeconfig généré (il contient les identifiants du cluster) dans le répertoire personnel de l'utilisateur :

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config
```

Le fichier copié pointe vers `https://127.0.0.1:6443`, ce qui est correct lorsque `kubectl` s'exécute sur le serveur. Pour utiliser `kubectl` depuis un portable, copiez-y le fichier et remplacez `127.0.0.1` par `<SERVER_IP>` (le port 6443 doit être accessible ; voir les pages sur le pare-feu et l'accès distant).

> **Attention :** le fichier est un instantané. Si K3s est réinstallé, les certificats changent et la copie cesse de fonctionner ; copiez-la de nouveau.

## Vérification

```bash
kubectl get node
kubectl get pods -A
kubectl -n kube-system get svc traefik
```

Résultat attendu : nœud `Ready`, pods `coredns`, `traefik`, `local-path-provisioner`, `metrics-server` en `Running`, et le service `traefik` de type `LoadBalancer` avec `<SERVER_IP>` comme IP externe.

| Symptôme | Solution |
|---|---|
| `permission denied` sur `/etc/rancher/k3s/k3s.yaml` | `kubectl` lit le fichier par défaut réservé à root ; faites l'étape 3 et vérifiez `echo $KUBECONFIG` |
| `connection refused` | `sudo systemctl status k3s` ; redémarrez avec `sudo systemctl restart k3s` ; journaux : `sudo journalctl -u k3s -f` |
| Nœud `NotReady` pendant des minutes | RAM/disque insuffisants ou conflit de port sur 80/443/6443 ; consultez le journal |
| Les images construites avec Docker sont introuvables par les pods | K3s utilise son propre containerd ; importez : `docker save <image> \| sudo k3s ctr images import -` |

## Arrêt et désinstallation

```bash
sudo systemctl stop k3s              # stop the cluster (data is kept)
sudo /usr/local/bin/k3s-killall.sh   # also kill all pod processes
sudo /usr/local/bin/k3s-uninstall.sh # remove K3s and all its cluster data
```

> **Attention :** `k3s-uninstall.sh` supprime l'état du cluster. Les données stockées dans des répertoires `hostPath` en dehors de `/var/lib/rancher/k3s` ne sont pas touchées.

Suite : [Ingress avec Traefik et une première application](ingress-traefik-first-app.md)
