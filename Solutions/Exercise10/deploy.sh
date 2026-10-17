#!/usr/bin/env bash
#
# Exercise 10 - Multi-Node Kubernetes cluster with multiple apps + ReplicaSets
#
# Mirrors the brief end to end:
#   Step 0  remove any existing devops-multinode profile (clean slate)
#   Step 1a start a 3-node Minikube cluster (profile devops-multinode)
#   Step 1b enable the registry add-on
#   Step 4  docker build the two Flask images
#   Step 5  load the images into the cluster
#   Step 6  apply the two Deployments (podAntiAffinity spreads pods across nodes)
#   Step 7  apply the two NodePort Services
#   Step 8  verify the pods are Running and spread over the 3 nodes
#   Step 9/10 reach each Service (kubectl port-forward) and exercise it with curl
#
# Usage:
#   ./deploy.sh            # full run
#   ./deploy.sh --reuse    # keep an existing devops-multinode profile (skip Step 0)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Git Bash on Windows can hand native tools a truncated PATH; ensure docker's
# directory is reachable. `minikube`/`kubectl` must already be on PATH.
if command -v docker >/dev/null 2>&1; then
    PATH="$(dirname "$(command -v docker)"):$PATH"
    export PATH
fi

PROFILE="devops-multinode"
NODES=3
APP_DIR="app"
MAN_DIR="manifests"
PRODUCT_IMAGE="product-catalog:latest"
CART_IMAGE="shopping-cart:latest"
PRODUCT_SVC="product-catalog-service"
CART_SVC="shopping-cart-service"

REUSE=0
for arg in "$@"; do
  case "$arg" in
    --reuse) REUSE=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

cleanup_pf() { [ -n "${PF1:-}" ] && kill "$PF1" 2>/dev/null || true; [ -n "${PF2:-}" ] && kill "$PF2" 2>/dev/null || true; }
trap cleanup_pf EXIT

port_free() { ! netstat -ano 2>/dev/null | grep -qiE "[:.]$1[[:space:]].*LISTENING"; }
pick_port() { local p="$1"; while ! port_free "$p"; do p=$((p + 1)); done; echo "$p"; }

# ------------------------------------------------------------- [1/8] prereqs
echo "[1/8] Checking prerequisites"
command -v minikube >/dev/null 2>&1 || { echo "ERROR: minikube not found in PATH" >&2; exit 1; }
command -v kubectl  >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH"  >&2; exit 1; }
command -v docker   >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH"   >&2; exit 1; }
echo "  minikube: $(minikube version --short 2>/dev/null || minikube version | head -1)"
echo "  kubectl : $(kubectl version --client -o json 2>/dev/null | sed -n 's/.*"gitVersion": *"\([^"]*\)".*/\1/p' | head -1)"

# ------------------------------------------------ [2/8] multi-node cluster
echo "[2/8] Setting up the multi-node Minikube cluster (profile ${PROFILE})"
if [ "$REUSE" -eq 0 ]; then
  if minikube -p "$PROFILE" status >/dev/null 2>&1; then
    echo "  existing profile found -> deleting for a clean start (brief Step 0)"
    minikube -p "$PROFILE" delete
  fi
fi
if minikube -p "$PROFILE" status 2>/dev/null | grep -q "Running"; then
  echo "  reusing running profile"
else
  echo "  starting ${NODES} nodes (driver docker, runtime docker)..."
  minikube start --nodes "$NODES" -p "$PROFILE" --force \
    --driver=docker --container-runtime=docker --cpus=2 --memory=1800mb
fi
kubectl config use-context "$PROFILE" >/dev/null
echo "  nodes:"
kubectl get nodes --no-headers | sed 's/^/    /'

echo "  enabling the registry add-on (brief Step 1b)"
minikube -p "$PROFILE" addons enable registry 2>&1 | grep -iE "enabled|verifying" | sed 's/^/    /' || true

# ------------------------------------------------------------ [3/8] images
echo "[3/8] Building the two application images (brief Step 4)"
docker build -q -t "$PRODUCT_IMAGE" -f "$APP_DIR/Dockerfile.product" "$APP_DIR" >/dev/null
docker build -q -t "$CART_IMAGE"    -f "$APP_DIR/Dockerfile.shopping" "$APP_DIR" >/dev/null
echo "  built: $PRODUCT_IMAGE, $CART_IMAGE"

# ------------------------------------------------------ [4/8] load images
echo "[4/8] Loading images into the cluster (brief Step 5)"
minikube -p "$PROFILE" image load "$PRODUCT_IMAGE" >/dev/null
minikube -p "$PROFILE" image load "$CART_IMAGE"    >/dev/null
echo "  verification (minikube ssh -- docker images):"
minikube -p "$PROFILE" ssh -- docker images --format '    {{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E "product-catalog|shopping-cart" || true

# --------------------------------------------------- [5/8] deployments
echo "[5/8] Applying Deployments (brief Step 6)"
kubectl apply -f "$MAN_DIR/product_catalog_deployment.yaml"
kubectl apply -f "$MAN_DIR/shopping_cart_deployment.yaml"

# ------------------------------------------------------ [6/8] services
echo "[6/8] Applying Services (brief Step 7)"
kubectl apply -f "$MAN_DIR/product_catalog_service.yaml"
kubectl apply -f "$MAN_DIR/shopping_cart_service.yaml"

# ------------------------------------ [7/8] verify distribution (Step 8)
echo "[7/8] Waiting for pods and verifying node distribution (brief Step 8)"
rollout_ok=0
for _ in $(seq 1 90); do
  p_ready="$(kubectl get pods -l app=product-catalog --no-headers 2>/dev/null | awk '$2=="1/1" && $3=="Running"{c++} END{print c+0}')"
  c_ready="$(kubectl get pods -l app=shopping-cart  --no-headers 2>/dev/null | awk '$2=="1/1" && $3=="Running"{c++} END{print c+0}')"
  if [ "$p_ready" = "2" ] && [ "$c_ready" = "3" ]; then rollout_ok=1; break; fi
  sleep 3
done
[ "$rollout_ok" -eq 1 ] || { echo "ERROR: pods not ready (product=${p_ready:-0}/2, cart=${c_ready:-0}/3)" >&2; kubectl get pods -o wide >&2; exit 1; }

kubectl get pods -o wide |
  awk 'NR==1 || /product-catalog|shopping-cart/ { printf "  %-38s %-6s %-9s %s\n", $1, $2, $3, $7 }'

prod_nodes="$(kubectl get pods -l app=product-catalog -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l | tr -d ' ')"
cart_nodes="$(kubectl get pods -l app=shopping-cart  -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l | tr -d ' ')"
echo "  product-catalog spread over ${prod_nodes} node(s) (expect 2)"
echo "  shopping-cart  spread over ${cart_nodes} node(s) (expect 3)"
[ "$prod_nodes" = "2" ] && [ "$cart_nodes" = "3" ] \
  || { echo "ERROR: pods are not spread as expected" >&2; exit 1; }

# --------------------------------------------- [8/8] access + curl (9-10)
echo "[8/8] Exercising the Services with curl (brief Steps 9-10)"
P1="$(pick_port 18080)"; P2="$(pick_port 18081)"
kubectl port-forward -n default "svc/${PRODUCT_SVC}" "${P1}:80" >/dev/null 2>&1 & PF1=$!
kubectl port-forward -n default "svc/${CART_SVC}"    "${P2}:80" >/dev/null 2>&1 & PF2=$!

for _ in $(seq 1 30); do
  curl -fsS -o /dev/null "http://127.0.0.1:${P1}/products" 2>/dev/null && \
  curl -fsS -o /dev/null "http://127.0.0.1:${P2}/cart"     2>/dev/null && break
  sleep 1
done

products="$(curl -fsS "http://127.0.0.1:${P1}/products")"
cart_get="$(curl -fsS "http://127.0.0.1:${P2}/cart")"
cart_post="$(curl -fsS -X POST "http://127.0.0.1:${P2}/cart" \
  -H "Content-Type: application/json" -d '{"id": 1, "name": "Laptop", "quantity": 1}')"

echo "  GET  /products -> ${products}"
echo "  GET  /cart     -> ${cart_get}"
echo "  POST /cart     -> ${cart_post}"

printf '%s' "$products"  | grep -q '"name": *"Laptop"' || printf '%s' "$products" | grep -q '"name":"Laptop"' \
  || { echo "ERROR: /products did not return the catalog" >&2; exit 1; }
printf '%s' "$cart_get"  | grep -q '^\[\]$' \
  || { echo "ERROR: /cart was not empty initially" >&2; exit 1; }
printf '%s' "$cart_post" | grep -q 'Laptop' \
  || { echo "ERROR: POST /cart did not add the item" >&2; exit 1; }

cat <<EOF

============================================================
 Exercise 10 complete
============================================================
 Profile  : ${PROFILE} (${NODES} nodes, driver docker)
 Images   : ${PRODUCT_IMAGE}, ${CART_IMAGE} (loaded into the cluster)
 Pods     : product-catalog x2 (on ${prod_nodes} nodes), shopping-cart x3 (on ${cart_nodes} nodes)
 Services : ${PRODUCT_SVC}, ${CART_SVC} (NodePort)
 Checks   : GET /products -> catalog, GET /cart -> [], POST /cart -> item added
============================================================
EOF

echo
echo "Useful commands:"
echo "  kubectl get pods -o wide"
echo "  minikube -p ${PROFILE} service ${PRODUCT_SVC}   # opens a tunnel/browser"
echo "  cleanup: ./cleanup.sh [--cluster] [--images]"
