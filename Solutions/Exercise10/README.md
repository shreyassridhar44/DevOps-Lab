# Exercise 10 — Multi-Node Minikube Cluster with Multiple Apps + ReplicaSets

> Brief: [`Exercises/10-Minikube-Multi-Node-Multi-App-Minikube-Deployment.md`](../../Exercises/10-Minikube-Multi-Node-Multi-App-Minikube-Deployment.md)

The brief asks for a **3-node Minikube cluster** (profile `devops-multinode`) that
hosts an e-commerce platform made of two Flask apps:

* **Product Catalog** (AppA) → `GET /products`, **2 replicas**
* **Shopping Cart** (AppB) → `GET`/`POST /cart`, **3 replicas**

Both use **`podAntiAffinity`** so no two replicas of the same app share a node —
Product Catalog lands on 2 of the 3 nodes and Shopping Cart on all 3. The brief
then exposes both as **NodePort** Services and exercises them with `curl`.

This folder automates the whole thing end-to-end with one script and reproduces
the brief's *Step 8* pod distribution and *Step 10* curl responses exactly.

---

## What the brief asks for (and where it lives here)

| Brief step | What it says | Where this solution does it |
|---|---|---|
| Step 0 | `minikube stop` / `minikube delete` (clean slate) | `deploy.sh` **[2/8]** deletes only the `devops-multinode` profile if present |
| Step 1a | `minikube start --nodes 3 -p devops-multinode --force` | `deploy.sh` **[2/8]** (same, plus explicit docker driver/runtime + node sizing) |
| Step 1b | `minikube -p devops-multinode addons enable registry` | `deploy.sh` **[2/8]** |
| Step 2 | Flask `product_catalog.py` | [`app/product_catalog.py`](app/product_catalog.py) — verbatim from the brief |
| Step 3 | Flask `shopping_cart.py` | [`app/shopping_cart.py`](app/shopping_cart.py) — verbatim from the brief |
| Step 4 | `Dockerfile.product` / `Dockerfile.shopping` + `docker build` | [`app/Dockerfile.product`](app/Dockerfile.product), [`app/Dockerfile.shopping`](app/Dockerfile.shopping); built in `deploy.sh` **[3/8]** |
| Step 5 | `minikube image load …` into the cluster | `deploy.sh` **[4/8]** |
| Step 6 | Two Deployments (2 + 3 replicas, `podAntiAffinity`) | [`manifests/product_catalog_deployment.yaml`](manifests/product_catalog_deployment.yaml), [`manifests/shopping_cart_deployment.yaml`](manifests/shopping_cart_deployment.yaml); applied in **[5/8]** |
| Step 7 | Two NodePort Services | [`manifests/product_catalog_service.yaml`](manifests/product_catalog_service.yaml), [`manifests/shopping_cart_service.yaml`](manifests/shopping_cart_service.yaml); applied in **[6/8]** |
| Step 8 | `kubectl get pods -o wide` → replicas on different nodes | `deploy.sh` **[7/8]** asserts spread (product on 2 nodes, cart on 3) |
| Step 9 | `minikube service …` opens a browser URL | `deploy.sh` **[8/8]** uses `kubectl port-forward` + `curl` (scriptable equivalent) |
| Step 10 | `curl` `/products`, `/cart`, `POST /cart` | `deploy.sh` **[8/8]** runs all three and fails if any mismatches |

---

## Files

| File | Purpose |
|---|---|
| `app/product_catalog.py` | Flask `GET /products` returning the 3-product catalog (from the brief) |
| `app/shopping_cart.py` | Flask `GET`/`POST /cart` with an in-memory cart (from the brief) |
| `app/Dockerfile.product` | Image for Product Catalog (from the brief) |
| `app/Dockerfile.shopping` | Image for Shopping Cart (from the brief) |
| `manifests/product_catalog_deployment.yaml` | Product Catalog Deployment, 2 replicas + `podAntiAffinity` (from the brief) |
| `manifests/shopping_cart_deployment.yaml` | Shopping Cart Deployment, 3 replicas + `podAntiAffinity` (namespace fixed, see Deviations) |
| `manifests/product_catalog_service.yaml` | Product Catalog `NodePort` Service (from the brief) |
| `manifests/shopping_cart_service.yaml` | Shopping Cart `NodePort` Service (from the brief) |
| `deploy.sh` | One-shot: cluster → images → load → Deployments → Services → verify spread → curl |
| `cleanup.sh` | Removes the K8s objects (and optionally the cluster and images) |

---

## Prerequisites

* Docker running locally (this solution uses the **docker** Minikube driver)
* `minikube` (≥ 1.33), `kubectl`, `bash` (Git Bash on Windows), `curl`
* Enough free RAM: a 3-node cluster plus any other containers. If nodes fail to
  start, see **Troubleshooting** (`exit status 0xc0000142`).

---

## Usage

```bash
cd Solutions/Exercise10

# Full run: 3-node cluster, build+load images, deploy, verify spread, curl
./deploy.sh

# Reuse an already-running devops-multinode profile (skip the clean slate)
./deploy.sh --reuse

# Afterwards, remove what it created
./cleanup.sh                        # delete the Deployments + Services only
./cleanup.sh --cluster              # also `minikube delete -p devops-multinode`
./cleanup.sh --cluster --images     # also remove the two local images
```

On Windows run it with Git Bash (`bash.exe`), not PowerShell/cmd.

### Sample run

```
[1/8] Checking prerequisites
  minikube: v1.39.0
  kubectl : v1.36.1
[2/8] Setting up the multi-node Minikube cluster (profile devops-multinode)
  starting 3 nodes (driver docker, runtime docker)...
* Done! kubectl is now configured to use "devops-multinode" cluster ...
  nodes:
    devops-multinode       Ready      control-plane   ...
    devops-multinode-m02   Ready      <none>          ...
    devops-multinode-m03   Ready      <none>          ...
  enabling the registry add-on (brief Step 1b)
    * The 'registry' addon is enabled
[3/8] Building the two application images (brief Step 4)
  built: product-catalog:latest, shopping-cart:latest
[4/8] Loading images into the cluster (brief Step 5)
  verification (minikube ssh -- docker images):
shopping-cart:latest
product-catalog:latest
[5/8] Applying Deployments (brief Step 6)
deployment.apps/product-catalog created
deployment.apps/shopping-cart created
[6/8] Applying Services (brief Step 7)
service/product-catalog-service created
service/shopping-cart-service created
[7/8] Waiting for pods and verifying node distribution (brief Step 8)
  NAME                                   READY  STATUS    NODE
  product-catalog-7cb85d4f-97kb2         1/1    Running   devops-multinode-m03
  product-catalog-7cb85d4f-9zzm6         1/1    Running   devops-multinode-m02
  shopping-cart-6858b5f797-ph4tn         1/1    Running   devops-multinode-m02
  shopping-cart-6858b5f797-xrbhd         1/1    Running   devops-multinode-m03
  shopping-cart-6858b5f797-zxv8d         1/1    Running   devops-multinode
  product-catalog spread over 2 node(s) (expect 2)
  shopping-cart  spread over 3 node(s) (expect 3)
[8/8] Exercising the Services with curl (brief Steps 9-10)
  GET  /products -> [{"id":1,"name":"Laptop","price":1200},{"id":2,"name":"Phone","price":800},{"id":3,"name":"Headphones","price":150}]
  GET  /cart     -> []
  POST /cart     -> [{"id":1,"name":"Laptop","quantity":1}]

============================================================
 Exercise 10 complete
============================================================
 Profile  : devops-multinode (3 nodes, driver docker)
 Pods     : product-catalog x2 (on 2 nodes), shopping-cart x3 (on 3 nodes)
 Checks   : GET /products -> catalog, GET /cart -> [], POST /cart -> item added
============================================================
```

---

## How it works

### 1. The multi-node cluster

`[2/8]` runs (the brief's Step 1a, plus explicit sizing):

```bash
minikube start --nodes 3 -p devops-multinode --force \
  --driver=docker --container-runtime=docker --cpus=2 --memory=1800mb
```

This creates a control-plane node (`devops-multinode`) plus two workers
(`…-m02`, `…-m03`). `--force` is required because we intentionally run the
docker driver with root privileges (the brief says the same). The `registry`
add-on is then enabled (brief Step 1b) so images can be shared across nodes.

### 2. Images and loading

`[3/8]` builds `product-catalog:latest` and `shopping-cart:latest` from the two
Dockerfiles. `[4/8]` loads them into the cluster with `minikube image load`
(brief Step 5) and confirms via `minikube ssh -- docker images`. Because the
Deployments set `imagePullPolicy: Never`, the pods resolve the pre-loaded local
image and never hit a remote registry.

### 3. Deployments and anti-affinity

`[5/8]` applies the two Deployments. Each has `replicas` (2 / 3) and:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels: {app: product-catalog}   # or app: shopping-cart
      topologyKey: "kubernetes.io/hostname"
```

`requiredDuringScheduling` is a hard rule: the scheduler will **not** place two
same-app pods on one host. With 3 nodes that forces Product Catalog onto 2 nodes
and Shopping Cart onto all 3 — exactly the brief's *Step 8* distribution.

### 4. Services and access

`[6/8]` applies the two `NodePort` Services. The brief's Step 9 uses
`minikube service …`, which opens a browser and blocks on a tunnel. For a
scriptable check, `[8/8]` instead `kubectl port-forward`s each Service to a
free local port and `curl`s it — the same traffic path, automatable end-to-end.

### 5. Verification

`[7/8]` waits for `product-catalog` to have 2 Ready pods and `shopping-cart` to
have 3, then reads each pod's `nodeName` and fails unless they land on 2 and 3
distinct nodes respectively. `[8/8]` asserts the three `curl` results match the
brief's *Step 10* expected JSON.

---

## Verification

`deploy.sh` exits `0` only if every check passes:

| Check | Expected |
|---|---|
| Nodes | 3 nodes `Ready` (`devops-multinode`, `-m02`, `-m03`) |
| Images loaded | `product-catalog:latest`, `shopping-cart:latest` present in the cluster |
| Product Catalog | 2 pods `1/1 Running`, spread over **2** nodes |
| Shopping Cart | 3 pods `1/1 Running`, spread over **3** nodes |
| `GET /products` | the 3-item catalog JSON |
| `GET /cart` | `[]` (empty initially) |
| `POST /cart` | `[{…Laptop…quantity:1}]` |

Manual spot-check:

```bash
kubectl get nodes -o wide
kubectl get pods -o wide
minikube -p devops-multinode service product-catalog-service
minikube -p devops-multinode service shopping-cart-service
```

---

## Deviations from the brief (and why)

| # | Brief does | This solution does | Why |
|---|---|---|---|
| 1 | Step 0: `minikube stop` / `minikube delete` (all profiles) | Deletes only the `devops-multinode` profile, and only if it exists | Avoids nuking an unrelated profile (e.g. a shared `minikube`); idempotent |
| 2 | Step 1a: `minikube start --nodes 3 -p devops-multinode --force` | Same, plus `--driver=docker --container-runtime=docker --cpus=2 --memory=1800mb` | Pins driver/runtime for reproducibility and bounds per-node RAM so 3 nodes fit the Docker VM |
| 3 | Step 6: `shopping_cart_deployment.yaml` uses `namespace: devops-exercise` | Uses `namespace: default` | The brief never creates `devops-exercise`, and the Shopping Cart Service **and every verification step** live in `default`. In `devops-exercise` the Deployment fails to apply and the Service selects nothing |
| 4 | Step 9: `minikube service …` opens a browser/tunnel | `kubectl port-forward` + `curl` | Opens a browser and blocks; the port-forward path is scriptable so the whole exercise runs headlessly |
| 5 | Step 5 text: "load into Minikube's registry" | Uses `minikube -p … image load` | Same command as the brief's own snippet; the registry add-on is still enabled (Step 1b) as the brief requires |

> **Deviation 3 is the important one.** As printed, the brief's Shopping Cart
> Deployment targets a namespace that does not exist; the manifests here put it
> in `default` (like the Service) so the exercise actually works.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Nodes fail with `exit status 0xc0000142` (DLL init failed) | The host is out of memory, so Windows can't spawn the `docker.exe` process for a new node. Free host RAM (quit other apps, or restart Docker Desktop), raise Docker Desktop's Memory slider, or lower `--memory=` in `deploy.sh` |
| `Docker Desktop only has N MiB available` warning | Docker Desktop's VM is small for 3 nodes + other containers. Increase **Settings → Resources → Memory** to ≥ 2.25 GB |
| Pods stuck `ImagePullBackOff`/`ErrImageNeverPull` | The image wasn't loaded. Re-run `deploy.sh`, or `minikube -p devops-multinode image load product-catalog:latest` (and the shopping-cart image) |
| Shopping Cart pods not created / Service finds no endpoints | The `devops-exercise` namespace issue from Deviation 3 — apply the `default`-namespace manifests in `manifests/` |
| Two same-app pods land on one node | `podAntiAffinity` not applied — confirm the `affinity` block is present, or fewer than the needed nodes are `Ready` (cart needs 3, product needs 2) |
| `kubectl port-forward` says port already in use | `deploy.sh` auto-picks the first free port from 18080; rerun or forward manually |
| Third node won't start on a low-RAM machine | `--cpus=2 --memory=1800mb` × 3 exceeds the Docker VM. Reduce to `--memory=1200mb` (or 2 nodes) in `deploy.sh` |

---

## Cleanup

```bash
./cleanup.sh                 # remove the Deployments + Services
./cleanup.sh --cluster       # also `minikube delete -p devops-multinode`
./cleanup.sh --cluster --images  # also remove product-catalog/shopping-cart images
```
