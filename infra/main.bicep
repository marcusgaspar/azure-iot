targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
@description('Short base name for resource naming (e.g., "aiotdemo").')
@minLength(3)
@maxLength(20)
param baseName string = 'aiotdemo'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('IoT Hub SKU.')
@allowed(['F1', 'S1', 'S2', 'S3'])
param iotHubSku string = 'S1'

@description('ACR SKU.')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Standard'

@description('Name of the Arc-enrolled Kubernetes cluster that will run AIO. If deployEdgeVm=true, this is the name the new VM will register itself as.')
param arcClusterName string

@description('Deploy Azure IoT Operations extension onto the Arc cluster.')
param deployAio bool = true

// ---------------------------------------------------------------------------
// Optional: provision an Ubuntu 24.04 VM that runs K3s and Arc-enrolls itself.
// Useful for demo / test environments where no physical edge device exists.
//
// IMPORTANT — two-phase deployment when combined with `deployAio=true`:
//   1. Deploy first with deployEdgeVm=true and deployAio=false. Wait ~5 min
//      for cloud-init to finish (tail /var/log/edge-bootstrap.log over SSH or
//      run: az connectedk8s show -n <arcClusterName> -g <rg> until it exists).
//   2. Re-deploy with deployAio=true to install the AIO extension on the
//      now-Arc-enrolled cluster.
// ---------------------------------------------------------------------------
@description('Provision an Ubuntu 24.04 + K3s VM and Arc-enroll it. Demo-only.')
param deployEdgeVm bool = false

@description('Admin username for the edge VM (only used when deployEdgeVm=true).')
param vmAdminUsername string = 'azureuser'

@description('SSH public key for the edge VM admin user (required when deployEdgeVm=true).')
@secure()
param vmSshPublicKey string = ''

@description('Edge VM size. Default meets the AIO minimum (4 vCPU / 16 GiB).')
param vmSize string = 'Standard_D4s_v5'

@description('Source CIDR allowed to SSH into the edge VM. Tighten in non-demo envs.')
param vmSshSourceAddressPrefix string = '*'

@description('Resource tags applied to all resources.')
param tags object = {
  project: 'azure-iot-demo'
  managedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------
module iotHub 'modules/iothub.bicep' = {
  name: 'deploy-iothub'
  params: {
    baseName: baseName
    location: location
    skuName: iotHubSku
    tags: tags
  }
}

module acr 'modules/acr.bicep' = {
  name: 'deploy-acr'
  params: {
    baseName: baseName
    location: location
    skuName: acrSku
    tags: tags
  }
}

module edgeVm 'modules/edge-vm.bicep' = if (deployEdgeVm) {
  name: 'deploy-edge-vm'
  params: {
    baseName: baseName
    location: location
    tags: tags
    adminUsername: vmAdminUsername
    sshPublicKey: vmSshPublicKey
    vmSize: vmSize
    sshSourceAddressPrefix: vmSshSourceAddressPrefix
    arcClusterName: arcClusterName
  }
}

module aio 'modules/aio.bicep' = if (deployAio) {
  name: 'deploy-aio'
  params: {
    clusterName: arcClusterName
    acrId: acr.outputs.acrId
  }
  // When the edge VM is being created in the same deployment, ensure the VM
  // exists before AIO tries to reference the connected cluster. Note that the
  // VM resource finishing does NOT guarantee cloud-init / Arc enrollment has
  // completed — see the two-phase deployment note above.
  dependsOn: deployEdgeVm ? [ edgeVm ] : []
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('Hostname of the IoT Hub.')
output iotHubHostname string = iotHub.outputs.iotHubHostname

@description('Name of the IoT Hub.')
output iotHubName string = iotHub.outputs.iotHubName

@description('ACR login server.')
output acrLoginServer string = acr.outputs.acrLoginServer

@description('ACR name.')
output acrName string = acr.outputs.acrName

@description('Public IP of the edge VM (empty when deployEdgeVm=false).')
output edgeVmPublicIp string = deployEdgeVm ? edgeVm!.outputs.publicIpAddress : ''

@description('SSH command for the edge VM (empty when deployEdgeVm=false).')
output edgeVmSshCommand string = deployEdgeVm ? edgeVm!.outputs.sshCommand : ''
