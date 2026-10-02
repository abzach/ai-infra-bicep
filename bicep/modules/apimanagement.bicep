metadata description = 'Azure API Management service configured for the Consumption tier free-call allowance.'

@description('API Management service name. Must be globally unique.')
param serviceName string

@description('Azure region.')
param location string

@description('API Management SKU name. Consumption keeps this component on the serverless free-call allowance target.')
@allowed([
  'Consumption'
])
param skuName string = 'Consumption'

@description('Publisher email shown in API Management notifications and portal metadata.')
param publisherEmail string = 'admin@example.com'

@description('Publisher name shown in API Management notifications and portal metadata.')
param publisherName string = 'AI Infra'

@description('Resource tags to apply.')
param tags object = {}

resource apiManagement 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: serviceName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: 0
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    publicNetworkAccess: 'Enabled'
  }
}

output id string = apiManagement.id
output name string = apiManagement.name