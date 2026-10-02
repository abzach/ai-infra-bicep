metadata description = 'Microsoft Foundry account and project with private Agent Service network injection and AAD connections.'

type modelDeploymentConfig = {
  deploymentName: string
  modelName: string
  modelVersion: string
  skuName: string
  @minValue(1)
  capacityK: int
}

@description('Microsoft Foundry account name.')
param accountName string

@description('Microsoft Foundry project name.')
param projectName string

@description('Azure region.')
param location string

@description('Dedicated subnet resource ID for Agent Service network injection.')
param agentSubnetId string

@description('Azure Storage account resource ID used for Agent file storage.')
param storageAccountResourceId string

@description('Azure Storage blob endpoint used by the project connection.')
param storageBlobEndpoint string

@description('Cosmos DB account resource ID used for Agent thread storage.')
param cosmosDbAccountResourceId string

@description('Cosmos DB document endpoint used by the project connection.')
param cosmosDbEndpoint string

@description('Azure AI Search resource ID used for Agent vector stores.')
param aiSearchResourceId string

@description('Azure AI Search endpoint used by the project connection.')
param aiSearchEndpoint string

@description('Model deployments hosted by the Foundry account.')
param modelDeployments modelDeploymentConfig[]

@description('Log Analytics workspace resource ID used for diagnostics. Leave empty to skip.')
param logAnalyticsWorkspaceResourceId string = ''

@description('Resource tags to apply.')
param tags object = {}

#disable-next-line BCP036
resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetId
        useMicrosoftManagedNetwork: false
      }
    ]
    publicNetworkAccess: 'Disabled'
  }
}

@batchSize(1)
#disable-next-line BCP081
resource modelDeploymentResources 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = [for modelDeployment in modelDeployments: {
  parent: account
  name: modelDeployment.deploymentName
  sku: {
    name: modelDeployment.skuName
    capacity: modelDeployment.capacityK
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelDeployment.modelName
      version: modelDeployment.modelVersion
    }
  }
  dependsOn: [
    aiSearchConnection
  ]
}]

resource accountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceResourceId)) {
  name: 'send-to-law'
  scope: account
  properties: {
    workspaceId: logAnalyticsWorkspaceResourceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Private Microsoft Foundry Agent Service project.'
    displayName: projectName
  }
}

resource storageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: 'agent-storage'
  properties: {
    authType: 'AAD'
    category: 'AzureStorageAccount'
    target: storageBlobEndpoint
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageAccountResourceId
      location: location
    }
  }
}

resource cosmosDbConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: 'agent-cosmosdb'
  properties: {
    authType: 'AAD'
    category: 'CosmosDB'
    target: cosmosDbEndpoint
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosDbAccountResourceId
      location: location
    }
  }
  dependsOn: [
    storageConnection
  ]
}

resource aiSearchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: 'agent-search'
  properties: {
    authType: 'AAD'
    category: 'CognitiveSearch'
    target: aiSearchEndpoint
    metadata: {
      ApiType: 'Azure'
      ResourceId: aiSearchResourceId
      location: location
    }
  }
  dependsOn: [
    cosmosDbConnection
  ]
}

resource projectCognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, project.id, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: account
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output accountId string = account.id
output accountName string = account.name
output accountEndpoint string = account.properties.endpoint
output accountPrincipalId string = account.identity.principalId
output projectId string = project.id
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId
output storageConnectionName string = storageConnection.name
output cosmosDbConnectionName string = cosmosDbConnection.name
output aiSearchConnectionName string = aiSearchConnection.name