#!/usr/bin/env bash
# scripts/bootstrap.sh
#
# One-shot bootstrap script that:
#   1. Deploys Azure infrastructure (IoT Hub, ACR) via Bicep.
#   2. Arc-enrolls an existing Kubernetes cluster.
#   3. Bootstraps Flux GitOps onto the cluster.
#   4. Creates ACR pull credentials as a Kubernetes Secret for Flux.
#
# Prerequisites:
#   - Azure CLI logged in: az login
#   - kubectl pointing at the target cluster
#   - flux CLI installed: https://fluxcd.io/flux/installation/
#   - helm CLI installed (used internally by Flux bootstrap)
#
# Usage:
#   export SUBSCRIPTION_ID="<your-subscription-id>"
#   export RESOURCE_GROUP="rg-azure-iot-demo"
#   export LOCATION="eastus"
#   export BASE_NAME="aiotdemo"
#   export CLUSTER_NAME="my-edge-cluster"
#   export GITHUB_TOKEN="<PAT-with-repo-scope>"
#   export GITHUB_OWNER="<your-github-org-or-user>"
#   export GITHUB_REPO="azure-iot"
#   bash scripts/bootstrap.sh

set -euo pipefail

: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"
: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${LOCATION:=eastus}"
: "${BASE_NAME:=aiotdemo}"
: "${CLUSTER_NAME:?Set CLUSTER_NAME}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN}"
: "${GITHUB_OWNER:?Set GITHUB_OWNER}"
: "${GITHUB_REPO:=azure-iot}"

ACR_NAME="${BASE_NAME}acr"

echo "==> Setting subscription"
az account set --subscription "$SUBSCRIPTION_ID"

echo "==> Creating resource group (if not exists)"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

echo "==> Deploying Bicep infrastructure"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam \
               arcClusterName="$CLUSTER_NAME" \
  --name "bootstrap-$(date +%s)" \
  --output table

ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query loginServer -o tsv)

echo "==> Arc-enrolling cluster (skip if already enrolled)"
az connectedk8s connect \
  --name "$CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" || true

echo "==> Bootstrapping Flux onto the cluster"
export GITHUB_TOKEN
flux bootstrap github \
  --owner="$GITHUB_OWNER" \
  --repository="$GITHUB_REPO" \
  --branch=main \
  --path=gitops/clusters/edge-cluster \
  --personal \
  --components-extra=image-reflector-controller,image-automation-controller

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
