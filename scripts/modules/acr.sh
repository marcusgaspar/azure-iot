#!/usr/bin/env bash
# scripts/modules/acr.sh
#
# Provision the Azure Container Registry that stores the edge container
# images and serves them to the Arc-enrolled cluster.
#
# Env in : SUBSCRIPTION_ID, RESOURCE_GROUP, LOCATION, ACR_NAME, ACR_SKU, TAGS_KV
# Stdout : ACR login server (so callers can capture: SERVER=$(./acr.sh))

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env SUBSCRIPTION_ID RESOURCE_GROUP
ensure_cli

# ACR names must be 5-50 chars, alphanumeric only.
if [[ ! "$ACR_NAME" =~ ^[a-zA-Z0-9]{5,50}$ ]]; then
  die "ACR_NAME '$ACR_NAME' must be 5-50 alphanumeric characters."
fi

if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  log "ACR '$ACR_NAME' already exists — skipping create."
else
  log "Creating ACR '$ACR_NAME' ($ACR_SKU) in '$LOCATION'"
  # shellcheck disable=SC2086
  az acr create \
    --name "$ACR_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku "$ACR_SKU" \
    --admin-enabled false \
    --public-network-enabled true \
    --tags $TAGS_KV \
    --output none
fi

LOGIN_SERVER=$(az acr show \
  --name "$ACR_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query loginServer -o tsv)

log "ACR ready: $LOGIN_SERVER"
echo "$LOGIN_SERVER"
