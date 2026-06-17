#!/usr/bin/env bash
# scripts/modules/common.sh
#
# Shared helpers and environment defaults for all module scripts.
# Source this file from every module:   source "$(dirname "$0")/common.sh"

set -euo pipefail

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { printf '\033[1;36m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Required environment (set by the caller / deploy.sh)
# ---------------------------------------------------------------------------
require_env() {
  local missing=0
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      err "Missing required env var: $var"
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || die "Set the missing variables and retry."
}

# ---------------------------------------------------------------------------
# Auto-load scripts/.env if present (Option A configuration).
# Variables ALREADY exported in the calling shell take precedence (the file
# uses `export VAR=...` but we don't override pre-existing values).
# Path: <repo>/scripts/.env  — this file (common.sh) lives in scripts/modules/
# ---------------------------------------------------------------------------
_ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/.env"
if [[ -f "$_ENV_FILE" ]]; then
  # Source in a subshell-safe way: only set vars that are currently unset/empty.
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    # Skip blanks/comments
    [[ -z "${_line// }" || "${_line#\#}" != "$_line" ]] && continue
    # Strip optional leading `export `
    _kv="${_line#export }"
    _key="${_kv%%=*}"
    # Only honor lines that look like KEY=VALUE
    [[ "$_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ -z "${!_key:-}" ]]; then
      # Re-eval so $HOME and ${OTHER} expansions in the file work
      eval "export $_kv"
    fi
  done < "$_ENV_FILE"
  unset _line _kv _key
fi
unset _ENV_FILE

# ---------------------------------------------------------------------------
# Defaults (only used if caller / .env hasn't already exported them)
# ---------------------------------------------------------------------------
: "${LOCATION:=eastus}"
: "${BASE_NAME:=aiotdemo}"
: "${IOT_HUB_SKU:=S1}"
: "${IOT_HUB_CAPACITY:=1}"
: "${ACR_SKU:=Standard}"
: "${ARC_CLUSTER_NAME:=my-edge-cluster}"
: "${VM_ADMIN_USERNAME:=azureuser}"
: "${VM_SIZE:=Standard_D4s_v5}"
: "${VM_OS_DISK_SIZE_GB:=64}"
: "${VM_SSH_SOURCE_CIDR:=*}"

# Edge VM networking — CIDR blocks (override if they conflict with peered VNets).
# VM_SUBNET_CIDR MUST be inside VM_VNET_CIDR.
: "${VM_VNET_CIDR:=10.20.0.0/16}"
: "${VM_SUBNET_CIDR:=10.20.0.0/24}"

# Derived names (mirror the Bicep modules so existing references keep working)
: "${ACR_NAME:=${BASE_NAME//-/}acr}"
: "${IOT_HUB_NAME:=${BASE_NAME}-iothub}"
: "${VM_NAME:=${BASE_NAME}-edge-vm}"
: "${VM_NIC_NAME:=${BASE_NAME}-edge-nic}"
: "${VM_NSG_NAME:=${BASE_NAME}-edge-nsg}"
: "${VM_VNET_NAME:=${BASE_NAME}-edge-vnet}"
: "${VM_SUBNET_NAME:=default}"
: "${VM_PIP_NAME:=${BASE_NAME}-edge-pip}"

# Default resource tags as CLI-friendly space-separated key=value pairs.
# Override with: export TAGS_KV="project=iot env=dev managedBy=azcli"
: "${TAGS_KV:=project=azure-iot-demo managedBy=azcli}"

# ---------------------------------------------------------------------------
# CLI prerequisite checks
# ---------------------------------------------------------------------------
ensure_cli() {
  command -v az >/dev/null 2>&1 || die "Azure CLI ('az') is not installed."
  az account show >/dev/null 2>&1 || die "Run 'az login' before invoking these scripts."
  if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
    az account set --subscription "$SUBSCRIPTION_ID"
  fi
}

ensure_extension() {
  local ext="$1"
  if ! az extension show --name "$ext" >/dev/null 2>&1; then
    log "Installing az CLI extension: $ext"
    az extension add --name "$ext" --only-show-errors --upgrade
  fi
}

# ---------------------------------------------------------------------------
# Subscription-level resource-provider registration. Required for every
# component this demo provisions. Idempotent: 'register' is a no-op when the
# state is already Registered.
#
# Coverage:
#   IoT Hub               -> Microsoft.Devices
#   ACR                   -> Microsoft.ContainerRegistry
#   Edge VM (compute+net) -> Microsoft.Compute / Microsoft.Network / Microsoft.Storage
#   Arc-enabled K8s       -> Microsoft.Kubernetes / Microsoft.KubernetesConfiguration
#                            Microsoft.ExtendedLocation
#   Azure IoT Operations  -> Microsoft.IoTOperations / Microsoft.DeviceRegistry
#                            Microsoft.SecretSyncController
#
# NOTE: The legacy preview namespaces Microsoft.IoTOperationsMQ and
# Microsoft.IoTOperationsOrchestrator were retired when AIO went GA; do not
# add them back.
# ---------------------------------------------------------------------------
register_providers() {
  local providers=(
    # --- Core IaaS (usually auto-registered, but new MSDN/CSP subs may not be)
    Microsoft.Compute
    Microsoft.Network
    Microsoft.Storage
    # --- Demo PaaS resources
    Microsoft.Devices                 # IoT Hub
    Microsoft.ContainerRegistry       # ACR
    # --- Arc-enabled Kubernetes
    Microsoft.Kubernetes
    Microsoft.KubernetesConfiguration
    Microsoft.ExtendedLocation
    # --- Azure IoT Operations (GA)
    Microsoft.IoTOperations
    Microsoft.DeviceRegistry
    Microsoft.SecretSyncController
  )
  for ns in "${providers[@]}"; do
    local state
    state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "NotFound")
    if [[ "$state" != "Registered" ]]; then
      log "Registering provider $ns (current: $state)"
      az provider register --namespace "$ns" --wait \
        || warn "$ns registration returned non-zero (provider may be unavailable in this subscription/region)."
    fi
  done
}
