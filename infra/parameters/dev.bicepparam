using './main.bicep'

// ---------------------------------------------------------------------------
// Development environment parameters
// ---------------------------------------------------------------------------
param baseName = 'aiotdemo'
param location = 'eastus'
param iotHubSku = 'S1'
param acrSku = 'Standard'

// Set this to the name of your Arc-enrolled Kubernetes cluster.
// Run: az connectedk8s list -o table
param arcClusterName = 'my-edge-cluster'

param deployAio = true

param tags = {
  project: 'azure-iot-demo'
  environment: 'dev'
  managedBy: 'bicep'
}
