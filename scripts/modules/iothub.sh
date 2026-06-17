#!/usr/bin/env bash
# scripts/modules/iothub.sh
#
# Provision the Azure IoT Hub that the edge cluster forwards telemetry to.
#
# Env in : SUBSCRIPTION_ID, RESOURCE_GROUP, LOCATION,
#          IOT_HUB_NAME, IOT_HUB_SKU, IOT_HUB_CAPACITY, TAGS_KV
# Stdout : IoT Hub hostname

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env SUBSCRIPTION_ID RESOURCE_GROUP
ensure_cli
register_providers
ensure_extension azure-iot

if az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  log "IoT Hub '$IOT_HUB_NAME' already exists — skipping create."
else
  log "Creating IoT Hub '$IOT_HUB_NAME' ($IOT_HUB_SKU x $IOT_HUB_CAPACITY) in '$LOCATION'"
  # shellcheck disable=SC2086
  az iot hub create \
    --name "$IOT_HUB_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku "$IOT_HUB_SKU" \
    --unit "$IOT_HUB_CAPACITY" \
    --tags $TAGS_KV \
    --output none
fi

HOSTNAME=$(az iot hub show \
  --name "$IOT_HUB_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.hostName -o tsv)

log "IoT Hub ready: $HOSTNAME"
echo "$HOSTNAME"
