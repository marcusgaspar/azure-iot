using '../main.bicep'

// ---------------------------------------------------------------------------
// Development environment parameters
// ---------------------------------------------------------------------------
param baseName = 'aiotdemo'
param location = 'eastus'
param iotHubSku = 'S1'
param acrSku = 'Standard'

// Set this to the name your Arc-enrolled cluster has (or WILL have when
// deployEdgeVm=true and the VM Arc-enrolls itself).
// Run: az connectedk8s list -o table
param arcClusterName = 'my-edge-cluster'

// ---------------------------------------------------------------------------
// AIO + edge VM toggles
//
// Recommended for a clean demo from zero:
//   Step 1: deployEdgeVm = true,  deployAio = false   → provisions VM, k3s, Arc
//   (wait ~5 min, verify with: az connectedk8s show -n <arcClusterName> -g <rg>)
//   Step 2: deployEdgeVm = true,  deployAio = true    → installs AIO extension
// ---------------------------------------------------------------------------
param deployAio = false
param deployEdgeVm = true

// Edge VM settings (only used when deployEdgeVm=true)
param vmAdminUsername = 'azureuser'

// Paste your OpenSSH public key here (e.g., contents of ~/.ssh/id_rsa.pub).
// You can also override at deploy time:
//   az deployment group create ... -p vmSshPublicKey="$(cat ~/.ssh/id_rsa.pub)"
param vmSshPublicKey = ''

param vmSize = 'Standard_D4s_v5'

// Lock SSH down to your office / home IP in non-demo environments.
param vmSshSourceAddressPrefix = '*'

param tags = {
  project: 'azure-iot-demo'
  environment: 'dev'
  managedBy: 'bicep'
}
