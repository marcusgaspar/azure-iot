#!/usr/bin/env bash
# scripts/deploy.sh
#
# Orchestrates the modular Azure CLI deployment. Each step is a standalone
# script under scripts/modules/ and can also be run by itself.
#
# USAGE
#   bash scripts/deploy.sh [--skip-vm] [--skip-aio] [--only <step>]
#
# STEPS (default order)
#   rg        — resource group
#   acr       — Azure Container Registry
#   iothub    — IoT Hub
#   edge-vm   — Ubuntu 24.04 + K3s VM, Arc-enrolls itself via cloud-init
#   wait-arc  — poll until the Arc-connected cluster is registered
#   aio       — installs Azure IoT Operations on the Arc cluster
#
# REQUIRED ENV
#   SUBSCRIPTION_ID, RESOURCE_GROUP
#
# CONFIGURATION
#   Easiest: copy scripts/.env.example to scripts/.env and fill it in.
#   common.sh auto-loads scripts/.env. Variables already exported in your
#   shell take precedence over .env values.
#
# COMMON OVERRIDES (see scripts/modules/common.sh for the full list)
#   LOCATION, BASE_NAME, ARC_CLUSTER_NAME,
#   ACR_SKU, IOT_HUB_SKU,
#   VM_SIZE, VM_ADMIN_USERNAME, VM_SSH_PUBLIC_KEY (or VM_SSH_PUBLIC_KEY_FILE),
#   VM_SSH_SOURCE_CIDR

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"
# shellcheck source=modules/common.sh
source "$MODULES_DIR/common.sh"

require_env SUBSCRIPTION_ID RESOURCE_GROUP
ensure_cli

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
SKIP_VM=0
SKIP_AIO=0
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-vm)  SKIP_VM=1; shift ;;
    --skip-aio) SKIP_AIO=1; shift ;;
    --only)     ONLY="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0"; exit 0 ;;
    *) die "Unknown argument: $1 (try --help)" ;;
  esac
done

run_step() {
  local name="$1" script="$2"
  if [[ -n "$ONLY" && "$ONLY" != "$name" ]]; then return; fi
  log "===== $name ====="
  bash "$script"
}

# ---------------------------------------------------------------------------
# Custom step: wait until the Arc cluster is registered after edge-vm cloud-init
# ---------------------------------------------------------------------------
wait_for_arc() {
  log "Waiting for Arc-enrolled cluster '$ARC_CLUSTER_NAME' to appear (cloud-init can take 5-10 min)..."
  local max_attempts=90  # 90 * 10s = 15 min
  for i in $(seq 1 $max_attempts); do
    if az connectedk8s show -n "$ARC_CLUSTER_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
      log "Arc cluster registered after ~$((i*10))s."
      return 0
    fi
    sleep 10
  done
  die "Timed out waiting for Arc cluster. SSH the VM and inspect /var/log/edge-bootstrap.log + /var/log/cloud-init-output.log"
}

# ---------------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------------
log "Subscription: $SUBSCRIPTION_ID"
log "Resource group: $RESOURCE_GROUP ($LOCATION)"
log "Base name: $BASE_NAME"
log "Arc cluster name: $ARC_CLUSTER_NAME"

run_step rg     "$MODULES_DIR/rg.sh"
run_step acr    "$MODULES_DIR/acr.sh"
run_step iothub "$MODULES_DIR/iothub.sh"

if [[ $SKIP_VM -eq 0 ]]; then
  run_step edge-vm "$MODULES_DIR/edge-vm.sh"
fi

if [[ $SKIP_AIO -eq 0 ]]; then
  if [[ -z "$ONLY" || "$ONLY" == "wait-arc" ]]; then
    [[ $SKIP_VM -eq 0 ]] && wait_for_arc
  fi
  run_step aio "$MODULES_DIR/aio.sh"
fi

log "===== Deploy complete ====="
log "Next: run scripts/bootstrap.sh to wire up Flux + ACR pull secrets."
