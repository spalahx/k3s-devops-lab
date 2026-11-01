# Ingress avec Traefik et une première application

Déploie une application Nginx jetable et l'expose à l'adresse `http://<PROJECT_NAME>.<DOMAIN_BASE>` via le contrôleur Ingress Traefik que K3s installe par défaut. Exécutez-le une fois pour valider toute la chaîne (Deployment, Service, Ingress, DNS sur le portable) avant de déployer de vrais projets.

## Fonctionnement

```
browser --> <SERVER_IP>:80 --> Traefik (kube-system) --> Ingress rule (Host header) --> Service --> Pod
```

| Objet | Rôle |
|---|---|
| Deployment | Maintient N réplicas du Pod en fonctionnement |
| Service | Adresse interne stable pour les Pods sélectionnés par un label selector |
| Ingress | Règle « les requêtes pour l'hôte X vont au Service Y » ; Traefik la prend en compte automatiquement |

- K3s lie Traefik aux ports 80/443 du nœud (service `traefik`, de type `LoadBalancer`, servi par le ServiceLB intégré), de sorte que tous les projets partagent une seule IP et un seul port ; le routage se fait par l'en-tête `Host`.
- K3s définit Traefik comme classe d'Ingress par défaut, donc `ingressClassName` peut être omis.
- Rien n'a besoin d'être configuré sur Traefik lui-même.

## 1. Choisir un nom d'hôte

`<PROJECT_NAME>.<DOMAIN_BASE>`, par exemple `demo.home.test`. Utilisez un suffixe qui ne peut pas entrer en conflit avec le DNS réel ni avec le DNS multicast : `.test` ou un sous-domaine qui vous appartient. Évitez `.local` (réservé à mDNS ; sur macOS, les résolutions peuvent se bloquer plusieurs secondes).

## 2. Manifeste

`test-app.yaml` sur le serveur :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <PROJECT_NAME>-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <PROJECT_NAME>-web
  template:
    metadata:
      labels:
        app: <PROJECT_NAME>-web
    spec:
      containers:
      - name: web
        image: nginx:1.30.6
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: <PROJECT_NAME>-web
spec:
  selector:
    app: <PROJECT_NAME>-web
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <PROJECT_NAME>-web
spec:
  rules:
  - host: <PROJECT_NAME>.<DOMAIN_BASE>
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: <PROJECT_NAME>-web
            port:
              number: 80
```

Remplacez les placeholders par de vraies valeurs (`sed` ou un éditeur) avant d'appliquer. L'indentation YAML n'utilise que des espaces ; la valeur de `selector`/`labels` doit être identique dans le Deployment et le Service.

```bash
kubectl apply -f test-app.yaml
kubectl get pods,svc,ingress
```

## 3. Entrée hosts sur le portable

Le portable doit résoudre le nom vers le serveur. Ajoutez une ligne au fichier hosts (nécessite `sudo`) :

Fichier : `/etc/hosts` (`sudo nano /etc/hosts`)

```
<SERVER_IP> <PROJECT_NAME>.<DOMAIN_BASE>
```

Une IP, puis un ou plusieurs noms séparés par des espaces ; ne répétez pas le même nom sur plusieurs lignes. Chaque nouveau projet nécessite son propre nom sur cette ligne. Sur macOS, si une nouvelle entrée est ignorée : `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.

## Vérification

```bash
ping -c1 <PROJECT_NAME>.<DOMAIN_BASE>        # shows <SERVER_IP>
curl -I http://<PROJECT_NAME>.<DOMAIN_BASE>  # HTTP/1.1 200 OK
```

Navigateur : `http://<PROJECT_NAME>.<DOMAIN_BASE>` affiche « Welcome to nginx! ». Sans modifier hosts :

```bash
curl -H "Host: <PROJECT_NAME>.<DOMAIN_BASE>" http://<SERVER_IP>/
```

| Symptôme | Cause / solution |
|---|---|
| `404 page not found` (page de Traefik) | Le `host` de l'Ingress diffère du nom saisi, ou aucun Ingress n'existe : `kubectl get ingress` |
| Le nom ne se résout pas | Entrée hosts absente ou erreur de frappe ; `ping` doit afficher `<SERVER_IP>` |
| `ContainerCreating` pendant des minutes / `ImagePullBackOff` | Le serveur ne peut pas télécharger l'image ; `kubectl describe pod <pod>` et vérifiez Internet/DNS |
| `Pending` | CPU/RAM insuffisants ; voir `Events` dans `kubectl describe pod` |
| `error validating` lors de l'apply | Indentation ou tabulations dans le YAML |
| `502`/`Bad Gateway` | Le selector du Service ne correspond pas aux labels du Pod, ou `targetPort` incorrect ; `kubectl get endpoints` doit lister une IP de Pod |

## Nettoyage

```bash
kubectl delete -f test-app.yaml
```

Supprimez la ligne hosts si le nom ne sera pas réutilisé.

Suite : [Productivité du shell avec Starship](shell-productivity-starship.md)
