# Ollama in a Separate Namespace

Runs Ollama (a runtime for local LLMs such as `llama3` or `mistral`) in its own K3s namespace `ai-models` with hard CPU/RAM caps, so inference cannot starve the web projects on the same node. Optional; skip it on servers with less than about 8 GB of RAM or when a hosted LLM API is used instead. Inference here is CPU-only.

Manifests live in `~/k8s-infrastructure/ai-models/`.

## 1. Namespace and quota

```bash
mkdir -p ~/k8s-infrastructure/ai-models && cd ~/k8s-infrastructure/ai-models
kubectl create namespace ai-models
```

`ai-resource-quota.yaml` (a namespace-wide ceiling, independent of per-pod settings):

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

Size the numbers to the machine: for example, on a 16 GB node where web projects need 8-10 GB, give `ai-models` no more than 4-6 GB. Once a quota covers CPU/memory, every pod in the namespace must declare requests and limits, or it is rejected.

## 2. Deployment, storage, Service

Models are 2-40 GB and are not part of the image, so they need persistent storage. K3s ships the `local-path` StorageClass, which provisions a PVC on the node disk.

`ollama.yaml`:

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
    type: Recreate          # RWO volume: the old pod must stop before the new one starts
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
          image: ollama/ollama:0.5.7   # pin a current release instead of :latest
          ports:
            - containerPort: 11434
          env:
            - name: OLLAMA_KEEP_ALIVE
              value: "5m"               # unload the model from RAM after 5 idle minutes
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

| Setting | Why |
|---|---|
| `requests` / `limits` | `requests` is the reserved minimum used for scheduling; `limits` is the ceiling (CPU is throttled, memory overuse gets the pod OOM-killed). `limits.memory` must exceed the model's size |
| PVC on `/root/.ollama` | Without it, every pod restart re-downloads all models |
| `strategy: Recreate` | A `ReadWriteOnce` volume cannot be mounted by two pods during a rolling update |
| `OLLAMA_KEEP_ALIVE` | Frees RAM for other workloads when idle |

## 3. Pull a model

Pick a model that fits the memory limit (a 7-8B model at 4-bit quantization needs about 5 GB; 3B-class models fit in less):

```bash
kubectl -n ai-models exec -it deployment/ollama -- ollama pull llama3.2:3b
kubectl -n ai-models exec -it deployment/ollama -- ollama list
```

## 4. Exposure

The Service is `ClusterIP`: reachable only inside the cluster, at

```
http://ollama.ai-models.svc.cluster.local:11434
```

Pods in any namespace can call it with no further setup. From the laptop, use a tunnel rather than an Ingress:

```bash
kubectl -n ai-models port-forward svc/ollama 11434:11434
```

> **Warning:** Ollama has no authentication. Do not expose it through Ingress or a public port without an auth layer (for example, a Traefik basic-auth middleware) in front of it.

## 5. Call the API

From inside the cluster:

```bash
kubectl run curl-test -n default --rm -it --restart=Never --image=curlimages/curl -- \
  curl -s http://ollama.ai-models.svc.cluster.local:11434/api/generate \
  -d '{"model": "llama3.2:3b", "prompt": "Say hello in one sentence.", "stream": false}'
```

Via port-forward from the laptop:

```bash
curl -s localhost:11434/api/chat -d '{
  "model": "llama3.2:3b",
  "messages": [{"role": "user", "content": "Hello"}],
  "stream": false
}'
```

## Verify

```bash
kubectl -n ai-models get pods,pvc
kubectl -n ai-models describe resourcequota ai-models-quota
kubectl -n ai-models top pod        # requires metrics-server (bundled with K3s)
```

During generation, web projects in other namespaces should stay responsive (watch it in Grafana, see [Prometheus and Grafana](../08-monitoring/prometheus-grafana.md)).

## Gotchas

| Symptom | Cause / fix |
|---|---|
| Pod `Pending` | Requests exceed the quota or free node capacity; lower `requests` or raise the quota. Check `kubectl describe pod` |
| `OOMKilled` | Model larger than `limits.memory`; raise the limit or choose a smaller/more quantized model |
| `forbidden: failed quota ... must specify limits` | A pod in `ai-models` lacks requests/limits (the quota requires them) |
| Models re-downloaded after restart | PVC not mounted at `/root/.ollama` |
| Very slow replies | CPU-only inference; use smaller models and keep `limits.cpu` at what the node can spare |
| Sites slow down during inference | Quota too generous; lower `limits.cpu` / `limits.memory` |

Next: [Roadmap checklist](../99-appendix/roadmap-checklist.md)
