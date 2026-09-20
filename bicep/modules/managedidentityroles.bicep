metadata description = 'RBAC role assignments for the single shared managed identity used by Hub, Project, VM, and Automation.'

@description('Storage account name to grant Storage Blob Data Contributor to the managed identity.')
param storageAccountName string

@description('Key Vault name to grant Key Vault Secrets User to the managed identity.')
param keyVaultName string

@description('Azure OpenAI account name to grant Cognitive Services OpenAI User to the managed identity.')
param openAiAccountName string

@description('Grant the Storage Blob Data Contributor role. Set to false when the Storage account is not deployed.')
param grantStorageRole bool = true

@description('Principal ID of the single shared managed identity used across Hub, Project, VM, and Automation.')
param sharedIdentityPrincipalId string

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
resource storageBlobDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantStorageRole) {
  name: guid(resourceGroup().id, storageAccount.id, sharedIdentityPrincipalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: sharedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource kvSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, keyVault.id, sharedIdentityPrincipalId, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: sharedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Data-plane secret access (above) does not include the control-plane 'Microsoft.KeyVault/vaults/read'
// action that Microsoft.MachineLearningServices needs to validate the Key Vault when creating the
// AI Project workspace, since a Project inherits its Hub's Key Vault association. The built-in
// 'Key Vault Reader' role only covers 'Microsoft.KeyVault/vaults/*/read' (sub-resources), not the
// vault resource's own 'read' action, so the generic 'Reader' role is required here instead.
resource kvReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, keyVault.id, sharedIdentityPrincipalId, 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalId: sharedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource openAiUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, openAiAccount.id, sharedIdentityPrincipalId, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
    principalId: sharedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
