@description('Name of the Arc-connected Kubernetes cluster.')
param clusterName string

@description('Resource ID of the Azure Container Registry used by AIO.')
param acrId string

// ---------------------------------------------------------------------------
// Arc-connected cluster reference (must already be Arc-enrolled)
// ---------------------------------------------------------------------------
resource arcCluster 'Microsoft.Kubernetes/connectedClusters@2024-01-01' existing = {
  name: clusterName
}

// ---------------------------------------------------------------------------
// Azure IoT Operations extension
// Deploys the full AIO bundle (MQTT broker, data processor, connector for
// IoT Hub, secrets management) onto the Arc cluster.
// ---------------------------------------------------------------------------
resource aioExtension 'Microsoft.KubernetesConfiguration/extensions@2023-05-01' = {
  name: 'azure-iot-operations'
  scope: arcCluster
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    extensionType: 'microsoft.iotoperations'
    autoUpgradeMinorVersion: true
    releaseTrain: 'stable'
    configurationSettings: {
      // Enable the MQTT broker with default settings
      'mqttBroker.mode': 'distributed'
      // Enable the connector to forward telemetry to IoT Hub
      'iotHub.enabled': 'true'
      // Allow the image-pull secret from ACR to be used by workloads
      acrLoginServer: reference(acrId, '2023-07-01').loginServer
    }
  }
}

// ---------------------------------------------------------------------------
// Role assignment: allow the AIO managed identity to pull images from ACR
// ---------------------------------------------------------------------------
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acrId, aioExtension.id, acrPullRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: aioExtension.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('Principal ID of the AIO extension managed identity.')
output aioPrincipalId string = aioExtension.identity.principalId

@description('Name of the AIO extension.')
output aioExtensionName string = aioExtension.name
