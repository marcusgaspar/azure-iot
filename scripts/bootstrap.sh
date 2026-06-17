#!/usr/bin/env bash
# scripts/bootstrap.sh
#
# One-shot bootstrap script that:
#   1. Deploys Azure infrastructure (RG, ACR, IoT Hub, edge VM + Arc, AIO)
#      by invoking scripts/deploy.sh (modular Azure CLI scripts).
#   2. Bootstraps Flux GitOps onto the Arc-enrolled cluster.
#   3. Creates ACR pull credentials as Kubernetes Secrets for Flux + workloads.
#
# Prerequisites:
#   - Azure CLI logged in: az login
#   - flux CLI installed: https://fluxcd.io/flux/installation/
#   - For step 2+: a kubeconfig that points at the cluster identified by
#     CLUSTER_NAME. When the edge VM provisions itself, copy the kubeconfig:
#       scp azureuser@<edgeVmPublicIp>:/etc/rancher/k3s/k3s.yaml ~/.kube/edge
#       sed -i 's/127.0.0.1/<edgeVmPublicIp>/' ~/.kube/edge
#       export KUBECONFIG=~/.kube/edge
#
# Usage:
#   # Recommended: configure scripts/.env (copy from scripts/.env.example)
#   bash scripts/bootstrap.sh
#
#   # Or export inline:
#   export SUBSCRIPTION_ID="<your-subscription-id>"
#   export RESOURCE_GROUP="rg-azure-iot-demo"
#   export LOCATION="eastus"
#   export BASE_NAME="aiotdemo"
#   export CLUSTER_NAME="my-edge-cluster"          # also used as ARC_CLUSTER_NAME
#   export GITHUB_TOKEN="<PAT-with-repo-scope>"
#   export GITHUB_OWNER="<your-github-org-or-user>"
#   export GITHUB_REPO="azure-iot"
#   export VM_SSH_PUBLIC_KEY_FILE="$HOME/.ssh/id_rsa.pub"
#   bash scripts/bootstrap.sh
#
# Skip infra (e.g., already deployed) with:  SKIP_DEPLOY=1 bash scripts/bootstrap.sh
# Skip the demo VM (you have your own cluster) with:  SKIP_VM=1 ...
# Skip AIO (install it later) with:                   SKIP_AIO=1 ...

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-load scripts/.env if present (shell env wins over file values).
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    [[ -z "${_line// }" || "${_line#\#}" != "$_line" ]] && continue
    _kv="${_line#export }"
    _key="${_kv%%=*}"
    [[ "$_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -z "${!_key:-}" ]] && eval "export $_kv"
  done < "$SCRIPT_DIR/.env"
  unset _line _kv _key
fi

: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"
: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${LOCATION:=eastus}"
: "${BASE_NAME:=aiotdemo}"
: "${CLUSTER_NAME:?Set CLUSTER_NAME}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN}"
: "${GITHUB_OWNER:?Set GITHUB_OWNER}"
: "${GITHUB_REPO:=azure-iot}"

# deploy.sh consumes ARC_CLUSTER_NAME; mirror CLUSTER_NAME into it.
export SUBSCRIPTION_ID RESOURCE_GROUP LOCATION BASE_NAME
export ARC_CLUSTER_NAME="$CLUSTER_NAME"

# Derived: same naming convention as scripts/modules/common.sh
ACR_NAME="${BASE_NAME//-/}acr"

# ---------------------------------------------------------------------------
# 1) Infra (RG, ACR, IoT Hub, edge VM, AIO) via the modular deploy script
# ---------------------------------------------------------------------------
if [[ "${SKIP_DEPLOY:-0}" -eq 1 ]]; then
  echo "==> Skipping infra deployment (SKIP_DEPLOY=1)"
else
  echo "==> Running modular Azure CLI infra deployment"
  DEPLOY_ARGS=()
  [[ "${SKIP_VM:-0}"  -eq 1 ]] && DEPLOY_ARGS+=("--skip-vm")
  [[ "${SKIP_AIO:-0}" -eq 1 ]] && DEPLOY_ARGS+=("--skip-aio")
  bash "$SCRIPT_DIR/deploy.sh" "${DEPLOY_ARGS[@]}"
fi

ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query loginServer -o tsv)

# ---------------------------------------------------------------------------
# 2) Flux GitOps bootstrap
# ---------------------------------------------------------------------------
command -v kubectl >/dev/null 2>&1 || { echo "kubectl required for Flux bootstrap" >&2; exit 1; }
command -v flux    >/dev/null 2>&1 || { echo "flux CLI required: https://fluxcd.io/flux/installation/" >&2; exit 1; }

echo "==> Bootstrapping Flux onto the cluster"
export GITHUB_TOKEN
flux bootstrap github \
  --owner="$GITHUB_OWNER" \
  --repository="$GITHUB_REPO" \
  --branch=main \
  --path=gitops/clusters/edge-cluster \
  --personal \
  --components-extra=image-reflector-controller,image-automation-controller

# ---------------------------------------------------------------------------
# 3) ACR pull credentials for Flux Image Reflector + workloads
# ---------------------------------------------------------------------------
echo "==> Creating ACR pull credentials for Flux Image Reflector"
ACR_TOKEN=$(az acr token create \
  --name flux-image-pull \
  --registry "$ACR_NAME" \
  --scope-map _repositories_pull \
  --query "credentials.passwords[0].value" -o tsv)

kubectl create secret docker-registry acr-credentials \
  --namespace flux-system \
  --docker-server="$ACR_LOGIN_SERVER" \
  --docker-username=flux-image-pull \
  --docker-password="$ACR_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating ACR imagePullSecret for workloads"
kubectl create namespace video-analytics --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret docker-registry acr-pull-secret \
  --namespace video-analytics \
  --docker-server="$ACR_LOGIN_SERVER" \
  --docker-username=flux-image-pull \
  --docker-password="$ACR_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==> Bootstrap complete!"
echo "    ACR login server : $ACR_LOGIN_SERVER"
echo "    Cluster          : $CLUSTER_NAME"
echo ""
echo "    Next steps:"
echo "    1. Push a new image to ACR to trigger automated edge updates:"
echo "       az acr build --registry $ACR_NAME --image video-analytics:0.1.0 edge/video-analytics"
echo "    2. Watch Flux reconcile: flux get all -A"
echo "    3. Monitor detections in IoT Hub:"
echo "       az iot hub monitor-events --hub-name ${BASE_NAME}-iothub"
