# Ollama dans un namespace dédié

Exécute Ollama (un runtime pour LLM locaux tels que `llama3` ou `mistral`) dans son propre namespace K3s `ai-models` avec des plafonds stricts de CPU/RAM, afin que l'inférence ne prive pas de ressources les projets web du même nœud. Optionnel ; ignorez-le sur les serveurs avec moins d'environ 8 Go de RAM ou lorsqu'une API LLM hébergée est utilisée à la place. L'inférence ici se fait uniquement sur CPU.

Les manifestes se trouvent dans `~/k8s-infrastructure/ai-models/`.

## 1. Namespace et quota

```bash
mkdir -p ~/k8s-infrastructure/ai-models && cd ~/k8s-infrastructure/ai-models
kubectl create namespace ai-models
```

`ai-resource-quota.yaml` (un plafond à l'échelle du namespace, indépendant des paramètres par pod) :

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ai-models-quota
  namespace: ai-models
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "3"
    limits.memory: 6Gi
    persistentvolumeclaims: "1"
    requests.storage: 40Gi
```

```bash
kubectl apply -f ai-resource-quota.yaml
```

Dimensionnez les valeurs selon la machine : par exemple, sur un nœud de 16 Go où les projets web ont besoin de 8 à 10 Go, ne donnez pas plus de 4 à 6 Go à `ai-models`. Dès qu'un quota couvre le CPU/la mémoire, chaque pod du namespace doit déclarer des requests et des limits, sinon il est rejeté.

## 2. Deployment, stockage, Service

Les modèles font de 2 à 40 Go et ne font pas partie de l'image ; ils nécessitent donc un stockage persistant. K3s fournit la StorageClass `local-path`, qui provisionne un PVC sur le disque du nœud.

`ollama.yaml` :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ollama-data
  namespace: ai-models
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: 30Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
  namespace: ai-models
spec:
  replicas: 1
  strategy:
    type: Recreate          # volume RWO : l'ancien pod doit s'arrêter avant le démarrage du nouveau
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
    spec:
      containers:
        - name: ollama
          image: ollama/ollama:0.5.7   # épinglez une version récente au lieu de :latest
          ports:
            - containerPort: 11434
          env:
            - name: OLLAMA_KEEP_ALIVE
              value: "5m"               # décharge le modèle de la RAM après 5 minutes d'inactivité
            - name: OLLAMA_NUM_PARALLEL
              value: "1"
            - name: OLLAMA_MAX_LOADED_MODELS
              value: "1"
          resources:
            requests:
              cpu: "1"
              memory: 2Gi
            limits:
              cpu: "2"
              memory: 5Gi
          volumeMounts:
            - name: ollama-data
              mountPath: /root/.ollama
          readinessProbe:
            httpGet:
              path: /
              port: 11434
            initialDelaySeconds: 5
      volumes:
        - name: ollama-data
          persistentVolumeClaim:
            claimName: ollama-data
---
apiVersion: v1
kind: Service
metadata:
  name: ollama
  namespace: ai-models
spec:
  selector:
    app: ollama
  ports:
    - port: 11434
      targetPort: 11434
```

```bash
kubectl apply -f ollama.yaml
kubectl -n ai-models get pods -w
```

| Paramètre | Raison |
|---|---|
| `requests` / `limits` | `requests` est le minimum réservé utilisé pour la planification ; `limits` est le plafond (le CPU est limité, un dépassement de mémoire fait tuer le pod par OOM). `limits.memory` doit dépasser la taille du modèle |
| PVC sur `/root/.ollama` | Sans lui, chaque redémarrage du pod retélécharge tous les modèles |
| `strategy: Recreate` | Un volume `ReadWriteOnce` ne peut pas être monté par deux pods pendant une mise à jour progressive |
| `OLLAMA_KEEP_ALIVE` | Libère de la RAM pour les autres charges de travail en cas d'inactivité |

## 3. Télécharger un modèle

Choisissez un modèle qui tient dans la limite de mémoire (un modèle 7-8B quantifié en 4 bits nécessite environ 5 Go ; les modèles de classe 3B tiennent dans moins) :

```bash
kubectl -n ai-models exec -it deployment/ollama -- ollama pull llama3.2:3b
kubectl -n ai-models exec -it deployment/ollama -- ollama list
```

## 4. Exposition

Le Service est de type `ClusterIP` : accessible uniquement à l'intérieur du cluster, à l'adresse

```
http://ollama.ai-models.svc.cluster.local:11434
```

Les pods de n'importe quel namespace peuvent l'appeler sans configuration supplémentaire. Depuis le portable, utilisez un tunnel plutôt qu'un Ingress :

```bash
kubectl -n ai-models port-forward svc/ollama 11434:11434
```

> **Avertissement :** Ollama n'a pas d'authentification. Ne l'exposez pas via un Ingress ou un port public sans une couche d'authentification devant lui (par exemple, un middleware basic-auth de Traefik).

## 5. Appeler l'API

Depuis l'intérieur du cluster :

```bash
kubectl run curl-test -n default --rm -it --restart=Never --image=curlimages/curl -- \
  curl -s http://ollama.ai-models.svc.cluster.local:11434/api/generate \
  -d '{"model": "llama3.2:3b", "prompt": "Say hello in one sentence.", "stream": false}'
```

Via port-forward depuis le portable :

```bash
curl -s localhost:11434/api/chat -d '{
  "model": "llama3.2:3b",
  "messages": [{"role": "user", "content": "Hello"}],
  "stream": false
}'
```

## Vérification

```bash
kubectl -n ai-models get pods,pvc
kubectl -n ai-models describe resourcequota ai-models-quota
kubectl -n ai-models top pod        # nécessite metrics-server (fourni avec K3s)
```

Pendant la génération, les projets web des autres namespaces doivent rester réactifs (surveillez-le dans Grafana, voir [Prometheus et Grafana](../08-monitoring/prometheus-grafana.md)).

## Pièges courants

| Symptôme | Cause / solution |
|---|---|
| Pod en `Pending` | Les requests dépassent le quota ou la capacité libre du nœud ; réduisez `requests` ou augmentez le quota. Vérifiez `kubectl describe pod` |
| `OOMKilled` | Modèle plus grand que `limits.memory` ; augmentez la limite ou choisissez un modèle plus petit / plus quantifié |
| `forbidden: failed quota ... must specify limits` | Un pod dans `ai-models` n'a pas de requests/limits (le quota les exige) |
| Modèles retéléchargés après un redémarrage | PVC non monté sur `/root/.ollama` |
| Réponses très lentes | Inférence sur CPU uniquement ; utilisez des modèles plus petits et gardez `limits.cpu` à ce que le nœud peut céder |
| Les sites ralentissent pendant l'inférence | Quota trop généreux ; réduisez `limits.cpu` / `limits.memory` |

Suite : [Liste de contrôle de la feuille de route](../99-appendix/roadmap-checklist.md)
