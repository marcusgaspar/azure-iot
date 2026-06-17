#!/usr/bin/env bash
# scripts/modules/edge-vm.sh
#
# Provision an Ubuntu 24.04 + K3s edge VM and auto-Arc-enroll it.
#
# Creates: NSG (SSH only), VNet/subnet, Static Public IP, NIC, VM (Trusted
# Launch, System-Assigned MI), and assigns the "Kubernetes Cluster - Azure
# Arc Onboarding" role at the resource-group scope. Cloud-init then installs
# k3s and runs `az connectedk8s connect` using the MI.
#
# Env in : SUBSCRIPTION_ID, RESOURCE_GROUP, LOCATION,
#          VM_NAME, VM_SIZE, VM_OS_DISK_SIZE_GB,
#          VM_ADMIN_USERNAME, VM_SSH_PUBLIC_KEY (or VM_SSH_PUBLIC_KEY_FILE),
#          VM_SSH_SOURCE_CIDR, ARC_CLUSTER_NAME, TAGS_KV
# Stdout : Public IP address of the VM
#
# DEMO-ONLY: opens SSH (port 22) to VM_SSH_SOURCE_CIDR (default '*').
# Restrict it in any non-demo environment.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env SUBSCRIPTION_ID RESOURCE_GROUP ARC_CLUSTER_NAME
ensure_cli
ensure_extension connectedk8s
register_providers

# ---------------------------------------------------------------------------
# Resolve SSH public key
# ---------------------------------------------------------------------------
if [[ -z "${VM_SSH_PUBLIC_KEY:-}" ]]; then
  if [[ -n "${VM_SSH_PUBLIC_KEY_FILE:-}" && -r "$VM_SSH_PUBLIC_KEY_FILE" ]]; then
    VM_SSH_PUBLIC_KEY=$(<"$VM_SSH_PUBLIC_KEY_FILE")
  elif [[ -r "$HOME/.ssh/id_rsa.pub" ]]; then
    warn "VM_SSH_PUBLIC_KEY not set — falling back to ~/.ssh/id_rsa.pub"
    VM_SSH_PUBLIC_KEY=$(<"$HOME/.ssh/id_rsa.pub")
  else
    die "Provide VM_SSH_PUBLIC_KEY or VM_SSH_PUBLIC_KEY_FILE."
  fi
fi
export VM_SSH_PUBLIC_KEY

# ---------------------------------------------------------------------------
# Render cloud-init from template (envsubst in whitelist mode: only the listed vars are substituted; all other $... are passed through intact)
# ---------------------------------------------------------------------------
command -v envsubst >/dev/null 2>&1 || die "envsubst missing (apt-get install gettext-base)."

CLOUD_INIT_FILE=$(mktemp)
trap 'rm -f "$CLOUD_INIT_FILE"' EXIT

export ARC_CLUSTER_NAME RESOURCE_GROUP LOCATION
envsubst '${ARC_CLUSTER_NAME} ${RESOURCE_GROUP} ${LOCATION}' \
  < "$SCRIPT_DIR/cloud-init.yaml" > "$CLOUD_INIT_FILE"

# ---------------------------------------------------------------------------
# 1) NSG (SSH only)
# ---------------------------------------------------------------------------
if ! az network nsg show -g "$RESOURCE_GROUP" -n "$VM_NSG_NAME" >/dev/null 2>&1; then
  log "Creating NSG '$VM_NSG_NAME'"
  # shellcheck disable=SC2086
  az network nsg create \
    -g "$RESOURCE_GROUP" -n "$VM_NSG_NAME" -l "$LOCATION" \
    --tags $TAGS_KV --output none

  az network nsg rule create \
    -g "$RESOURCE_GROUP" --nsg-name "$VM_NSG_NAME" \
    -n AllowSSH --priority 1000 \
    --access Allow --direction Inbound --protocol Tcp \
    --source-address-prefixes "$VM_SSH_SOURCE_CIDR" \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 22 \
    --output none
else
  log "NSG '$VM_NSG_NAME' already exists."
fi

# ---------------------------------------------------------------------------
# 2) VNet + subnet (NSG attached at subnet level)
# ---------------------------------------------------------------------------
if ! az network vnet show -g "$RESOURCE_GROUP" -n "$VM_VNET_NAME" >/dev/null 2>&1; then
  log "Creating VNet '$VM_VNET_NAME' ($VM_VNET_CIDR) with subnet '$VM_SUBNET_NAME' ($VM_SUBNET_CIDR)"
  # shellcheck disable=SC2086
  az network vnet create \
    -g "$RESOURCE_GROUP" -n "$VM_VNET_NAME" -l "$LOCATION" \
    --address-prefixes "$VM_VNET_CIDR" \
    --subnet-name "$VM_SUBNET_NAME" \
    --subnet-prefixes "$VM_SUBNET_CIDR" \
    --tags $TAGS_KV --output none

  az network vnet subnet update \
    -g "$RESOURCE_GROUP" --vnet-name "$VM_VNET_NAME" -n "$VM_SUBNET_NAME" \
    --network-security-group "$VM_NSG_NAME" --output none
else
  log "VNet '$VM_VNET_NAME' already exists."
fi

# ---------------------------------------------------------------------------
# 3) Static Public IP (Standard SKU) with DNS label
# ---------------------------------------------------------------------------
if ! az network public-ip show -g "$RESOURCE_GROUP" -n "$VM_PIP_NAME" >/dev/null 2>&1; then
  RG_HASH=$(printf '%s' "${SUBSCRIPTION_ID}-${RESOURCE_GROUP}" | sha256sum | cut -c1-8)
  DNS_LABEL=$(echo "${BASE_NAME}-edge-${RG_HASH}" | tr '[:upper:]' '[:lower:]')
  log "Creating Public IP '$VM_PIP_NAME' (DNS label: $DNS_LABEL)"
  # shellcheck disable=SC2086
  az network public-ip create \
    -g "$RESOURCE_GROUP" -n "$VM_PIP_NAME" -l "$LOCATION" \
    --sku Standard --allocation-method Static --version IPv4 \
    --dns-name "$DNS_LABEL" \
    --tags $TAGS_KV --output none
else
  log "Public IP '$VM_PIP_NAME' already exists."
fi

# ---------------------------------------------------------------------------
# 4) NIC
# ---------------------------------------------------------------------------
if ! az network nic show -g "$RESOURCE_GROUP" -n "$VM_NIC_NAME" >/dev/null 2>&1; then
  log "Creating NIC '$VM_NIC_NAME'"
  # shellcheck disable=SC2086
  az network nic create \
    -g "$RESOURCE_GROUP" -n "$VM_NIC_NAME" -l "$LOCATION" \
    --vnet-name "$VM_VNET_NAME" --subnet "$VM_SUBNET_NAME" \
    --public-ip-address "$VM_PIP_NAME" \
    --tags $TAGS_KV --output none
else
  log "NIC '$VM_NIC_NAME' already exists."
fi

# ---------------------------------------------------------------------------
# 5) VM (Ubuntu 24.04 LTS, Trusted Launch, system-assigned MI, cloud-init)
# ---------------------------------------------------------------------------
if az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" >/dev/null 2>&1; then
  log "VM '$VM_NAME' already exists — skipping create."
else
  log "Creating VM '$VM_NAME' ($VM_SIZE, Ubuntu 24.04 LTS)"
  # shellcheck disable=SC2086
  az vm create \
    -g "$RESOURCE_GROUP" -n "$VM_NAME" -l "$LOCATION" \
    --image Canonical:ubuntu-24_04-lts:server:latest \
    --size "$VM_SIZE" \
    --admin-username "$VM_ADMIN_USERNAME" \
    --ssh-key-values "$VM_SSH_PUBLIC_KEY" \
    --nics "$VM_NIC_NAME" \
    --os-disk-size-gb "$VM_OS_DISK_SIZE_GB" \
    --storage-sku Premium_LRS \
    --security-type TrustedLaunch \
    --enable-secure-boot true --enable-vtpm true \
    --assign-identity '[system]' \
    --boot-diagnostics-storage '' \
    --custom-data "$CLOUD_INIT_FILE" \
    --tags $TAGS_KV \
    --output none
fi

# ---------------------------------------------------------------------------
# 6) Role assignment: VM MI -> "Kubernetes Cluster - Azure Arc Onboarding"
# ---------------------------------------------------------------------------
PRINCIPAL_ID=$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" \
  --query identity.principalId -o tsv)

if [[ -z "$PRINCIPAL_ID" || "$PRINCIPAL_ID" == "null" ]]; then
  die "VM has no system-assigned managed identity — cannot grant Arc onboarding role."
fi

RG_SCOPE=$(az group show -n "$RESOURCE_GROUP" --query id -o tsv)
ARC_ONBOARD_ROLE='Kubernetes Cluster - Azure Arc Onboarding'

# Two roles are required for the cloud-init Arc enrollment to succeed:
#   1. Reader on the RG     -> makes the subscription visible to the MI so
#                              'az login --identity' succeeds (the Arc role
#                              alone does NOT grant Microsoft.Resources/
#                              subscriptions/read, so without this the login
#                              fails with 'No subscriptions were found').
#   2. Arc onboarding role  -> actually permits creating connectedClusters.
assign_role() {
  local role="$1"
  if az role assignment list \
       --assignee "$PRINCIPAL_ID" \
       --role "$role" \
       --scope "$RG_SCOPE" \
       --query '[0].id' -o tsv | grep -q .; then
    log "Role '$role' already assigned to VM MI."
    return 0
  fi
  log "Granting '$role' to VM MI at RG scope"
  # Retry briefly: AAD propagation of a brand-new principal can lag a few seconds.
  for i in 1 2 3 4 5; do
    if az role assignment create \
         --assignee-object-id "$PRINCIPAL_ID" \
         --assignee-principal-type ServicePrincipal \
         --role "$role" \
         --scope "$RG_SCOPE" \
         --output none 2>/dev/null; then
      return 0
    fi
    warn "Role '$role' assignment failed (attempt $i/5); retrying in 10s..."
    sleep 10
  done
  die "Failed to assign role '$role' to VM MI after 5 attempts."
}

assign_role 'Reader'
assign_role "$ARC_ONBOARD_ROLE"

# ---------------------------------------------------------------------------
# Final: emit public IP
# ---------------------------------------------------------------------------
PUBLIC_IP=$(az network public-ip show \
  -g "$RESOURCE_GROUP" -n "$VM_PIP_NAME" \
  --query ipAddress -o tsv)
FQDN=$(az network public-ip show \
  -g "$RESOURCE_GROUP" -n "$VM_PIP_NAME" \
  --query dnsSettings.fqdn -o tsv)

log "Edge VM ready: ssh ${VM_ADMIN_USERNAME}@${PUBLIC_IP}   (FQDN: ${FQDN})"
log "Cloud-init runs k3s install + Arc enroll. Tail: sudo tail -f /var/log/edge-bootstrap.log"
log "Verify enrollment: az connectedk8s show -n $ARC_CLUSTER_NAME -g $RESOURCE_GROUP"
echo "$PUBLIC_IP"
