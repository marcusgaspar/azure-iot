#!/usr/bin/env bash
# scripts/modules/aio.sh
#
# Install the Azure IoT Operations extension onto an Arc-enrolled cluster
# and grant the AIO managed identity AcrPull on the demo ACR.
#
# Prerequisites:
#   * The cluster identified by ARC_CLUSTER_NAME is already Arc-enrolled
#     (run edge-vm.sh first, wait ~5 min, verify with 'az connectedk8s show').
#   * ACR identified by ACR_NAME already exists.
#
# Env in : SUBSCRIPTION_ID, RESOURCE_GROUP, ARC_CLUSTER_NAME, ACR_NAME

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env SUBSCRIPTION_ID RESOURCE_GROUP ARC_CLUSTER_NAME ACR_NAME
ensure_cli
ensure_extension k8s-extension
register_providers

# ---------------------------------------------------------------------------
# Sanity check: cluster must be Arc-enrolled before we can extend it
# ---------------------------------------------------------------------------
if ! az connectedk8s show -n "$ARC_CLUSTER_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
  die "Arc-connected cluster '$ARC_CLUSTER_NAME' not found in '$RESOURCE_GROUP'. Run edge-vm.sh and wait for cloud-init to finish."
fi

ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)

CLUSTER_ID=$(az connectedk8s show -n "$ARC_CLUSTER_NAME" -g "$RESOURCE_GROUP" --query id -o tsv)
AIO_NAME='azure-iot-operations'

# ---------------------------------------------------------------------------
# Install or update the AIO extension
# ---------------------------------------------------------------------------
if az k8s-extension show \
     --cluster-name "$ARC_CLUSTER_NAME" \
     --resource-group "$RESOURCE_GROUP" \
     --cluster-type connectedClusters \
     --name "$AIO_NAME" >/dev/null 2>&1; then
  log "AIO extension '$AIO_NAME' already present — skipping create."
else
  log "Installing AIO extension '$AIO_NAME' on cluster '$ARC_CLUSTER_NAME'"
  az k8s-extension create \
    --cluster-name "$ARC_CLUSTER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-type connectedClusters \
    --name "$AIO_NAME" \
    --extension-type microsoft.iotoperations \
    --release-train stable \
    --auto-upgrade-minor-version true \
    --configuration-settings "mqttBroker.mode=distributed" \
    --configuration-settings "iotHub.enabled=true" \
    --configuration-settings "acrLoginServer=${ACR_LOGIN_SERVER}" \
    --output none
fi

# ---------------------------------------------------------------------------
# Grant the AIO extension's managed identity AcrPull on the ACR
# ---------------------------------------------------------------------------
AIO_PRINCIPAL_ID=$(az k8s-extension show \
  --cluster-name "$ARC_CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-type connectedClusters \
  --name "$AIO_NAME" \
  --query identity.principalId -o tsv)

if [[ -z "$AIO_PRINCIPAL_ID" || "$AIO_PRINCIPAL_ID" == "null" ]]; then
  warn "AIO extension has no managed identity yet (extension still provisioning?). Skipping AcrPull assignment."
else
  if az role assignment list \
       --assignee-object-id "$AIO_PRINCIPAL_ID" \
       --assignee-principal-type ServicePrincipal \
       --role AcrPull --scope "$ACR_ID" \
       --query '[0].id' -o tsv | grep -q .; then
    log "AcrPull already assigned to AIO MI on $ACR_NAME."
  else
    log "Granting AcrPull on $ACR_NAME to AIO managed identity"
    for i in 1 2 3 4 5; do
      if az role assignment create \
           --assignee-object-id "$AIO_PRINCIPAL_ID" \
           --assignee-principal-type ServicePrincipal \
           --role AcrPull --scope "$ACR_ID" \
           --output none 2>/dev/null; then
        break
      fi
      warn "Role assignment failed (attempt $i/5); retrying in 10s..."
      sleep 10
    done
  fi
fi

log "AIO ready on cluster '$ARC_CLUSTER_NAME' (id: $CLUSTER_ID)."
