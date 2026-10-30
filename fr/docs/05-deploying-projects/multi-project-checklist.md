# Faire tourner plusieurs projets côte à côte

Liste de contrôle pour ajouter le deuxième projet, puis chaque suivant, sur un même nœud K3s sans collisions. Appliquez-la à chaque fois avant le `kubectl apply` d'un nouveau projet.

## Liste de contrôle par projet

| # | Élément | Règle |
|---|---|---|
| 1 | Namespace | Un par projet : `kubectl create namespace <PROJECT_NAME>` ; `metadata.namespace` renseigné dans chaque manifeste |
| 2 | Noms d'objets | Préfixe du projet sur les Deployments, Services, Ingresses (`<PROJECT_NAME>-db-service`, jamais `db`) |
| 3 | Labels | `app: <PROJECT_NAME>[-component]` unique ; les sélecteurs correspondent aux labels des Pods |
| 4 | Noms d'hôte | `<PROJECT_NAME>.<DOMAIN_BASE>` et `<PROJECT_NAME>-pma.<DOMAIN_BASE>` uniques ; ajoutés au `/etc/hosts` du client (ou au DNS) |
| 5 | Hôte de la base | `DB_HOST` et `PMA_HOST` = Service de base de ce projet |
| 6 | hostPath | Répertoires `k8s-local/mysql-data` et de code propres à chaque projet ; deux Pods ne montent jamais le même répertoire de données MySQL |
| 7 | Image locale | Tag unique `<PROJECT_NAME>-php:latest`, importé dans containerd |
| 8 | Secret | `<PROJECT_NAME>-secret` propre, avec son propre mot de passe de base |
| 9 | Ports | Pas de `hostPort`/`NodePort` sauf nécessité ; voir ci-dessous |
| 10 | Ressources | `requests`/`limits` définis sur chaque conteneur |

## Ports

Tout le HTTP passe par Traefik sur 80/443, routé par nom d'hôte ; les projets n'ont donc besoin d'aucun port public propre. Évitez `hostPort` et `type: NodePort` pour les applications web. Si un service doit être joignable directement (SSH vers un Pod, client de base de données), attribuez des NodePorts dans la plage 30000-32767 et consignez-les dans une liste unique pour qu'ils n'entrent jamais en collision :

| Projet | Service | NodePort |
|---|---|---|
| `<PROJECT_NAME>` | `<PROJECT_NAME>-db-service` | `30001` (exemple) |

Préférez `kubectl port-forward` pour un accès ponctuel : il n'ouvre rien de façon permanente.

## Limites de ressources

Un nœud unique partage la RAM et le CPU entre tous les projets, et un MySQL qui s'emballe peut déclencher l'OOM killer du nœud pour tout le monde.

```yaml
resources:
  requests: { cpu: 100m, memory: 256Mi }   # réservé pour l'ordonnancement
  limits:   { memory: 1Gi }                # plafond strict : le dépasser tue le conteneur
```

Vous pouvez en option plafonner un namespace entier :

```bash
kubectl -n <PROJECT_NAME> create quota <PROJECT_NAME>-quota --hard=requests.memory=2Gi,limits.memory=4Gi,pods=10
```

Les Pods qui ne définissent pas de requests/limits sont alors rejetés ; définissez-les donc d'abord dans chaque manifeste. Vérifiez la consommation réelle :

```bash
kubectl top pods -A          # nécessite metrics-server (fourni avec K3s)
```

## Accès entre namespaces (tests d'intégration)

Les Services sont joignables depuis n'importe quel namespace via leur nom DNS complet :

```
<service>.<namespace>.svc.cluster.local
```

Exemple : l'application du projet A qui appelle l'API du projet B, ou un Pod de test qui atteint une base :

```bash
kubectl -n <PROJECT_NAME> run dns-test --rm -it --image=busybox:1.36 --restart=Never -- \
  wget -qO- http://<OTHER_PROJECT>-service.<OTHER_PROJECT>.svc.cluster.local/
```

Au sein d'un même namespace, le nom court (`<PROJECT_NAME>-db-service`) suffit. N'utilisez la forme complète que pour des liens délibérés entre projets ; par défaut, les namespaces ne sont pas isolés au niveau réseau. Restreignez avec une `NetworkPolicy` si un projet ne doit pas être joignable par les autres.

## Nettoyage

```bash
kubectl delete namespace <PROJECT_NAME>                    # tous les objets du projet
sudo rm -rf ~/workspace/<PROJECT_GROUP>/<PROJECT_NAME>/k8s-local/mysql-data   # fichiers de la base (irréversible)
sudo k3s ctr images rm docker.io/library/<PROJECT_NAME>-php:latest
docker rmi <PROJECT_NAME>-php:latest
```

Supprimez ensuite les lignes de `/etc/hosts` et le répertoire des manifestes sous `~/k8s-infrastructure/projects/`. Supprimer un namespace ne supprime pas les données `hostPath` ; faites un dernier `mysqldump` avant de les effacer.

## Vérifier

```bash
kubectl get ns
kubectl get ingress -A          # tous les hôtes doivent être différents
kubectl get svc -A | grep -c db # chaque projet a son propre Service de base dans son propre namespace
kubectl top nodes
```

Suite : [Liste de contrôle de la feuille de route](../99-appendix/roadmap-checklist.md)
