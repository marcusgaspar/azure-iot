#!/usr/bin/env bash
# scripts/modules/rg.sh
#
# Create (idempotent) the resource group that hosts the demo.
#
# Env in : SUBSCRIPTION_ID, RESOURCE_GROUP, LOCATION, TAGS_KV
# Side   : creates the RG if it does not exist.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env SUBSCRIPTION_ID RESOURCE_GROUP
ensure_cli

if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  log "Resource group '$RESOURCE_GROUP' already exists — skipping create."
else
  log "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'"
  # shellcheck disable=SC2086
  az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags $TAGS_KV \
    --output none
fi

log "Resource group ready: $RESOURCE_GROUP"
