metadata description = 'Least-privilege role assignments for a Microsoft Foundry project identity on the Agent Service backing resources in the workload resource group.'

@description('Azure Storage account name.')
param storageAccountName string

@description('Cosmos DB account name.')
param cosmosDbAccountName string

@description('Azure AI Search service name.')
param aiSearchName string

@description('Principal ID of the Microsoft Foundry project system-assigned identity.')
param projectPrincipalId string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosDbAccountName
}

resource aiSearch 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: aiSearchName
}

resource storageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, projectPrincipalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource storageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, projectPrincipalId, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource cosmosDbOperator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosDbAccount.id, projectPrincipalId, '230815da-be43-4aae-9cb4-875f7bd000aa')
  scope: cosmosDbAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '230815da-be43-4aae-9cb4-875f7bd000aa')
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource cosmosDataContributorRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2024-11-15' existing = {
  parent: cosmosDbAccount
  name: '00000000-0000-0000-0000-000000000002'
}

resource cosmosDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: cosmosDbAccount
  name: guid(cosmosDbAccount.id, projectPrincipalId, cosmosDataContributorRole.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: cosmosDataContributorRole.id
    scope: cosmosDbAccount.id
  }
}

resource searchIndexDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiSearch.id, projectPrincipalId, '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  scope: aiSearch
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiSearch.id, projectPrincipalId, '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  scope: aiSearch
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
  }
}