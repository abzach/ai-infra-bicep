metadata description = 'Least-privilege RBAC role assignments for the AI Hub and VM managed identities.'

@description('Storage account name to grant Storage Blob Data Contributor to the managed identity.')
param storageAccountName string

@description('Key Vault name to grant Key Vault Secrets User to the managed identity.')
param keyVaultName string

@description('Azure OpenAI account name to grant Cognitive Services OpenAI User to the managed identity.')
param openAiAccountName string

@description('Principal ID of the managed identity assigned to the AI Hub.')
param hubIdentityPrincipalId string

@description('Principal ID of the managed identity assigned to the VM.')
param vmIdentityPrincipalId string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openAiAccountName
}

// The Hub manages AI project artifacts and needs read/write access to its backing storage.
resource hubStorageBlobDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, storageAccount.id, hubIdentityPrincipalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: hubIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// The VM only reads bootstrap artifacts, whereas the Hub needs artifact read/write access.
resource vmStorageBlobDataReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, storageAccount.id, vmIdentityPrincipalId, '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
    principalId: vmIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource hubKvSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, keyVault.id, hubIdentityPrincipalId, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: hubIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource vmKvSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, keyVault.id, vmIdentityPrincipalId, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: vmIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource hubOpenAiUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, openAiAccount.id, hubIdentityPrincipalId, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
    principalId: hubIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource vmOpenAiUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, openAiAccount.id, vmIdentityPrincipalId, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
    principalId: vmIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
