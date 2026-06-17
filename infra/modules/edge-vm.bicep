// ---------------------------------------------------------------------------
// edge-vm.bicep
//
// Provisions an Ubuntu 24.04 LTS VM in Azure that simulates an edge device:
//   * single-node K3s Kubernetes cluster
//   * Arc-enrolled automatically via cloud-init using the VM's system-assigned
//     managed identity (no secrets required)
//   * kernel tunings required by Azure IoT Operations (inotify, file-max)
//   * Trusted Launch + boot diagnostics for easy troubleshooting
//
// Demo/test environment only:
//   * Public IP + SSH open to `sshSourceAddressPrefix` (defaults to "*"; tighten it)
//   * Single replica, no HA, Premium_LRS OS disk
//
// Prerequisites (subscription level – cannot be done from a RG-scoped Bicep):
//   az provider register --namespace Microsoft.Kubernetes
//   az provider register --namespace Microsoft.KubernetesConfiguration
//   az provider register --namespace Microsoft.ExtendedLocation
// ---------------------------------------------------------------------------

@description('Base name used to derive VM and networking resource names.')
param baseName string

@description('Azure region for all resources in this module.')
param location string = resourceGroup().location

@description('Resource tags applied to every resource created here.')
param tags object = {}

@description('Admin username on the VM.')
param adminUsername string = 'azureuser'

@description('SSH public key (OpenSSH format) used for the admin user.')
@secure()
param sshPublicKey string

@description('VM size. The default meets the AIO minimum (4 vCPU / 16 GiB RAM).')
param vmSize string = 'Standard_D4s_v5'

@description('OS disk size (GiB). AIO requires at least 30 GiB free.')
@minValue(30)
param osDiskSizeGB int = 64

@description('Source CIDR allowed to reach the VM over SSH. "*" = anywhere (demo only).')
param sshSourceAddressPrefix string = '*'

@description('Name to register the cluster as in Azure Arc.')
param arcClusterName string

// ---------------------------------------------------------------------------
// Naming
// ---------------------------------------------------------------------------
var vmName     = '${baseName}-edge-vm'
var nicName    = '${baseName}-edge-nic'
var nsgName    = '${baseName}-edge-nsg'
var vnetName   = '${baseName}-edge-vnet'
var subnetName = 'default'
var pipName    = '${baseName}-edge-pip'

// ---------------------------------------------------------------------------
// Cloud-init: applied on first boot to install k3s and Arc-enroll the cluster.
// We use format() to inject Bicep values (Bicep multi-line strings do NOT
// interpolate ${...}, so format placeholders {0}, {1}, ... are used instead).
// ---------------------------------------------------------------------------
var cloudInitTemplate = '''#cloud-config
package_update: true
package_upgrade: false
packages:
  - curl
  - jq
  - ca-certificates
  - apt-transport-https
  - gnupg
  - lsb-release
write_files:
  - path: /etc/sysctl.d/99-aio.conf
    permissions: '0644'
    content: |
      fs.inotify.max_user_instances = 8192
      fs.inotify.max_user_watches = 524288
      fs.file-max = 100000
runcmd:
  # 1) Apply kernel tunings required by AIO / K3s
  - sysctl --system

  # 2) Install Azure CLI (Microsoft's official installer)
  - curl -sL https://aka.ms/InstallAzureCLIDeb | bash

  # 3) Install single-node K3s with world-readable kubeconfig and no Traefik
  - curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode=644 --disable=traefik" sh -

  # 4) Wait for the API server to become Ready (max ~5 min)
  - |
      for i in $(seq 1 60); do
        if KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get nodes 2>/dev/null | grep -q ' Ready '; then
          echo "k3s is Ready"; break
        fi
        sleep 5
      done

  # 5) Login to Azure using the VM's system-assigned managed identity
  - az login --identity

  # 6) Install the connectedk8s CLI extension (helm/kubectl come bundled)
  - az extension add --name connectedk8s --yes --upgrade

  # 7) Arc-enroll the K3s cluster (idempotent: --yes + retry-safe)
  - |
      az connectedk8s connect \
        --name "{0}" \
        --resource-group "{1}" \
        --location "{2}" \
        --kube-config /etc/rancher/k3s/k3s.yaml \
        --tags "deployedBy=bicep" \
        --yes \
        2>&1 | tee -a /var/log/edge-bootstrap.log

  # 8) Mark completion (poll this from outside to know when enrollment finishes)
  - echo "[bootstrap] arc enrollment finished at $(date -Iseconds)" >> /var/log/edge-bootstrap.log
'''

var cloudInit = format(cloudInitTemplate, arcClusterName, resourceGroup().name, location)

// ---------------------------------------------------------------------------
// Networking
// ---------------------------------------------------------------------------
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: sshSourceAddressPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [ '10.20.0.0/16' ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.20.0.0/24'
          networkSecurityGroup: { id: nsg.id }
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: pipName
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('${baseName}-edge-${uniqueString(resourceGroup().id)}')
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: '${vnet.id}/subnets/${subnetName}' }
          publicIPAddress: { id: publicIp.id }
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// VM (Ubuntu 24.04 LTS, Trusted Launch, system-assigned managed identity)
// ---------------------------------------------------------------------------
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGB
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
        provisionVMAgent: true
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nic.id }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Role assignment: grant the VM's managed identity the built-in role
// required to register a Kubernetes cluster with Azure Arc.
//
// Built-in role: "Kubernetes Cluster - Azure Arc Onboarding"
// ---------------------------------------------------------------------------
var arcOnboardingRoleId = '34e09817-6cbe-4d01-b1a2-e0eac5743d41'

resource arcOnboardingAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, vm.id, arcOnboardingRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', arcOnboardingRoleId)
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('VM resource ID.')
output vmId string = vm.id

@description('VM name.')
output vmName string = vm.name

@description('Public IP address assigned to the VM (use to SSH).')
output publicIpAddress string = publicIp.properties.ipAddress

@description('Fully-qualified DNS name of the VM.')
output fqdn string = publicIp.properties.dnsSettings.fqdn

@description('SSH command (after cloud-init completes – takes ~5 min).')
output sshCommand string = 'ssh ${adminUsername}@${publicIp.properties.dnsSettings.fqdn}'

@description('Name the cluster will register itself as in Azure Arc.')
output arcClusterName string = arcClusterName
