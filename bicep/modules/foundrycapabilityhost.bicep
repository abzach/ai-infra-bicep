metadata description = 'Project capability host binding Microsoft Foundry Agent Service to private backing-resource connections.'

@description('Microsoft Foundry account name.')
param accountName string

@description('Microsoft Foundry project name.')
param projectName string

@description('Project capability host name.')
param capabilityHostName string = 'agents'

@description('Project connection name for Azure Storage.')
param storageConnectionName string

@description('Project connection name for Cosmos DB thread storage.')
param cosmosDbConnectionName string

@description('Project connection name for Azure AI Search vector stores.')
param aiSearchConnectionName string

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: account
  name: projectName
}

resource capabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: project
  name: capabilityHostName
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    storageConnections: [
      storageConnectionName
    ]
    threadStorageConnections: [
      cosmosDbConnectionName
    ]
    vectorStoreConnections: [
      aiSearchConnectionName
    ]
  }
}

output name string = capabilityHost.name