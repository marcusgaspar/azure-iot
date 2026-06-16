@description('Base name used to derive resource names.')
param baseName string

@description('Azure region for the IoT Hub.')
param location string

@description('IoT Hub SKU name.')
@allowed(['F1', 'S1', 'S2', 'S3'])
param skuName string = 'S1'

@description('IoT Hub SKU capacity (number of units).')
param skuCapacity int = 1

@description('Resource tags.')
param tags object = {}

// ---------------------------------------------------------------------------
// IoT Hub
// ---------------------------------------------------------------------------
resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: '${baseName}-iothub'
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  properties: {
    messagingEndpoints: {
      fileNotifications: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601: 'PT1H'
        maxDeliveryCount: 10
      }
    }
    enableFileUploadNotifications: false
    cloudToDevice: {
      maxDeliveryCount: 10
      defaultTtlAsIso8601: 'PT1H'
      feedback: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601: 'PT1H'
        maxDeliveryCount: 10
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('Resource ID of the IoT Hub.')
output iotHubId string = iotHub.id

@description('Hostname of the IoT Hub.')
output iotHubHostname string = iotHub.properties.hostName

@description('Name of the IoT Hub.')
output iotHubName string = iotHub.name
