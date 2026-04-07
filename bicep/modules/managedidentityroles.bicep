metadata description = 'RBAC role assignments for the user-assigned managed identity. Keeps role assignments separate from identity creation to avoid the ResourceDeployedMultipleTimes diagnostic that occurs when the same identity module is called twice.'

@description('Storage account name to grant Storage Blob Data Contributor to the managed identity.')
param storageAccountName string

@description('Key Vault name to grant Key Vault Secrets User to the managed identity.')
param keyVaultName string

@description('Azure OpenAI account name to grant Cognitive Services OpenAI User to the managed identity.')
param openAiAccountName string

@description('Principal ID of the managed identity. Used as stable GUID seed for role assignment names.')
param identityPrincipalId string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openAiAccountName
}

// Storage Blob Data Contributor — allows the managed identity to read/write blobs.
resource storageBlobDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, storageAccount.id, identityPrincipalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Secrets User — allows the managed identity to read secrets.
resource kvSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, keyVault.id, identityPrincipalId, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Cognitive Services OpenAI User — allows the managed identity to call the OpenAI inference endpoint.
resource openAiUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, openAiAccount.id, identityPrincipalId, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
