@description('Base name used to derive resource names.')
param baseName string

@description('Azure region for the ACR instance.')
param location string

@description('ACR SKU.')
@allowed(['Basic', 'Standard', 'Premium'])
param skuName string = 'Standard'

@description('Resource tags.')
param tags object = {}

// ---------------------------------------------------------------------------
// Azure Container Registry
// ---------------------------------------------------------------------------
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: replace('${baseName}acr', '-', '')
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('Resource ID of the Azure Container Registry.')
output acrId string = acr.id

@description('Login server URL of the Azure Container Registry.')
output acrLoginServer string = acr.properties.loginServer

@description('Name of the Azure Container Registry.')
output acrName string = acr.name
