metadata description = 'AI Foundry project linked to a hub.'

@description('AI Project workspace name.')
param projectName string

@description('Azure region.')
param location string

@description('Resource ID of the Hub workspace.')
param hubResourceId string

@description('Resource tags to apply.')
param tags object = {}

resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: projectName
  location: location
  tags: tags
  kind: 'Project'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
  }
  properties: {
    hubResourceId: hubResourceId
    publicNetworkAccess: 'Disabled'
    allowPublicAccessWhenBehindVnet: false
  }
}

output id string = aiProject.id
output name string = aiProject.name
