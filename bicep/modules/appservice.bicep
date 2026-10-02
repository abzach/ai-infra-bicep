metadata description = 'Azure App Service (Linux) on the F1 Free plan.'

@description('App Service Plan name.')
param appServicePlanName string

@description('App Service (Web App) name. Must be globally unique.')
param appServiceName string

@description('Azure region.')
param location string

@description('App Service Plan SKU. F1 keeps this component at the $0 free-tier target.')
@allowed([
  'F1'
])
param skuName string = 'F1'

@description('Resource tags to apply.')
param tags object = {}

// F1 is Free/shared compute and does not support VNet integration or private endpoints,
// so this is a deliberately public surface like Static Web Apps; do not put secrets in it.
resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: 'Free'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource appService 'Microsoft.Web/sites@2024-04-01' = {
  name: appServiceName
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      linuxFxVersion: 'PYTHON|3.12'
    }
  }
}

output id string = appService.id
output name string = appService.name
output defaultHostName string = appService.properties.defaultHostName
