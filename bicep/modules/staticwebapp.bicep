metadata description = 'Azure Static Web Apps resource configured for the Free hosting plan.'

@description('Static Web App name.')
param staticWebAppName string

@description('Azure region. Static Web Apps supports a subset of Azure regions.')
param location string

@description('Static Web Apps SKU. Free keeps this component at the $0 plan target.')
@allowed([
  'Free'
])
param skuName string = 'Free'

@description('Resource tags to apply.')
param tags object = {}

resource staticWebApp 'Microsoft.Web/staticSites@2024-04-01' = {
  name: staticWebAppName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
  }
}

output id string = staticWebApp.id
output name string = staticWebApp.name