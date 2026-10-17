#!/usr/bin/env bash
#
# Exercise 10 - remove the resources created by deploy.sh
#
# Usage:
#   ./cleanup.sh              # delete the K8s Deployments + Services only
#   ./cleanup.sh --cluster    # also `minikube delete` the devops-multinode profile
#   ./cleanup.sh --images     # also remove the local product-catalog/shopping-cart images
#   ./cleanup.sh --cluster --images   # everything
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if command -v docker >/dev/null 2>&1; then
    PATH="$(dirname "$(command -v docker)"):$PATH"
    export PATH
fi

PROFILE="devops-multinode"
MAN_DIR="manifests"
PRODUCT_IMAGE="product-catalog:latest"
CART_IMAGE="shopping-cart:latest"

REMOVE_CLUSTER=0
REMOVE_IMAGES=0
for arg in "$@"; do
  case "$arg" in
    --cluster) REMOVE_CLUSTER=1 ;;
    --images)  REMOVE_IMAGES=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH" >&2; exit 1; }

echo "[1/3] Deleting the Deployments and Services"
if kubectl get nodes >/dev/null 2>&1; then
  kubectl delete -f "$MAN_DIR/product_catalog_service.yaml"    --ignore-not-found >/dev/null
  kubectl delete -f "$MAN_DIR/shopping_cart_service.yaml"      --ignore-not-found >/dev/null
  kubectl delete -f "$MAN_DIR/product_catalog_deployment.yaml" --ignore-not-found >/dev/null
  kubectl delete -f "$MAN_DIR/shopping_cart_deployment.yaml"   --ignore-not-found >/dev/null
  echo "  removed product-catalog/shopping-cart Deployments + Services"
else
  echo "  no reachable cluster (already gone?)"
fi

echo "[2/3] Multi-node cluster (profile ${PROFILE})"
if [ "$REMOVE_CLUSTER" -eq 1 ]; then
  if command -v minikube >/dev/null 2>&1 && minikube -p "$PROFILE" status >/dev/null 2>&1; then
    minikube -p "$PROFILE" delete
    echo "  deleted profile ${PROFILE}"
  else
    echo "  profile not present (already gone)"
  fi
else
  echo "  kept (pass --cluster to 'minikube delete -p ${PROFILE}')"
fi

echo "[3/3] Local Docker images"
if [ "$REMOVE_IMAGES" -eq 1 ]; then
  docker image rm "$PRODUCT_IMAGE" "$CART_IMAGE" >/dev/null 2>&1 && echo "  removed images" || echo "  images not present (already gone)"
else
  echo "  kept (pass --images to remove ${PRODUCT_IMAGE} and ${CART_IMAGE})"
fi

echo
echo "Cleanup complete."
