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

@description('Name of the Arc-enrolled Kubernetes cluster that will run AIO.')
param arcClusterName string

@description('Deploy Azure IoT Operations extension onto the Arc cluster.')
param deployAio bool = true

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

module aio 'modules/aio.bicep' = if (deployAio) {
  name: 'deploy-aio'
  params: {
    clusterName: arcClusterName
    acrId: acr.outputs.acrId
  }
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
