metadata description = 'Private Azure AI Search service for Microsoft Foundry Agent Service vector stores.'

@description('Azure AI Search service name.')
param searchServiceName string

@description('Azure region.')
param location string

@description('Azure AI Search SKU used by Foundry Agent Service.')
@allowed([
  'standard'
])
param skuName string = 'standard'

@description('Resource tags to apply.')
param tags object = {}

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchServiceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: skuName
  }
  properties: {
    disableLocalAuth: true
    hostingMode: 'default'
    networkRuleSet: {
      bypass: 'None'
      ipRules: []
    }
    partitionCount: 1
    publicNetworkAccess: 'disabled'
    replicaCount: 1
    semanticSearch: 'disabled'
  }
}

output id string = searchService.id
output name string = searchService.name
output endpoint string = 'https://${searchService.name}.search.windows.net'