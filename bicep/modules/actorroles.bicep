metadata description = 'Role-based access control (RBAC) role assignments for admin and user actors across services.'

type actorAssignment = {
  objectId: string
  principalType: ('User' | 'Group' | 'ServicePrincipal')?
}

@description('Array of administrator actors granted highest level data-plane and control-plane roles.')
param adminActors actorAssignment[] = []

@description('Array of user actors granted permissions to use, operate, modify, and view services.')
param userActors actorAssignment[] = []

@description('Key Vault name.')
param keyVaultName string

@description('Azure OpenAI account name.')
param openAiAccountName string

@description('Storage account name. Pass empty string if storage is not deployed.')
param storageAccountName string = ''

@description('AI Hub workspace name. Pass empty string if AI Foundry is not deployed.')
param hubName string = ''

@description('AI Project workspace name. Pass empty string if AI Foundry is not deployed.')
param projectName string = ''

@description('Jumpbox VM name. Pass empty string if VM is not deployed.')
param vmName string = ''

@description('Log Analytics workspace name. Pass empty string if Log Analytics is not deployed.')
param logAnalyticsWorkspaceName string = ''

// Existing resource references in the current resource group scope
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openAiAccountName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: !empty(storageAccountName) ? storageAccountName : 'dummy-storage'
}

resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-10-01' existing = {
  name: !empty(hubName) ? hubName : 'dummy-hub'
}

resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-10-01' existing = {
  name: !empty(projectName) ? projectName : 'dummy-project'
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' existing = {
  name: !empty(vmName) ? vmName : 'dummy-vm'
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: !empty(logAnalyticsWorkspaceName) ? logAnalyticsWorkspaceName : 'dummy-law'
}

// ---------------------------------------------------------------------------
// ADMIN ROLE ASSIGNMENTS - Highest level across data and control plane
// ---------------------------------------------------------------------------

// Key Vault Administrator (00482a5a-887f-4fb3-b363-3b7fe8e74483)
resource adminKeyVaultAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: {
  name: guid(resourceGroup().id, keyVault.id, admin.objectId, '00482a5a-887f-4fb3-b363-3b7fe8e74483')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Key Vault Secrets Officer (b86a8fe4-44ce-4948-aee5-eccb2c155cd7)
resource adminKeyVaultSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: {
  name: guid(resourceGroup().id, admin.objectId, keyVault.id, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Cognitive Services OpenAI Contributor (a001fd3d-188f-4b5d-821b-7da978bf7442)
resource adminOpenAiContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: {
  name: guid(resourceGroup().id, openAiAccount.id, admin.objectId, 'a001fd3d-188f-4b5d-821b-7da978bf7442')
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a001fd3d-188f-4b5d-821b-7da978bf7442')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Cognitive Services Contributor (25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68)
resource adminCognitiveServicesContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: {
  name: guid(resourceGroup().id, openAiAccount.id, admin.objectId, '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68')
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Storage Blob Data Owner (b7e6dc6d-f1e8-4753-8033-0f276bb0955b)
resource adminStorageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: if (!empty(storageAccountName)) {
  name: guid(resourceGroup().id, storageAccount.id, admin.objectId, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Storage Account Contributor (17d1049b-9a84-46fb-8f53-869881c3d3ab)
resource adminStorageAccountContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: if (!empty(storageAccountName)) {
  name: guid(resourceGroup().id, storageAccount.id, admin.objectId, '17d1049b-9a84-46fb-8f53-869881c3d3ab')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Azure AI Administrator (b78c5d69-af96-48a3-bf8d-a8b4d589de94) on AI Hub
resource adminAiHubAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: if (!empty(hubName)) {
  name: guid(resourceGroup().id, aiHub.id, admin.objectId, 'b78c5d69-af96-48a3-bf8d-a8b4d589de94')
  scope: aiHub
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b78c5d69-af96-48a3-bf8d-a8b4d589de94')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Azure AI Administrator (b78c5d69-af96-48a3-bf8d-a8b4d589de94) on AI Project
resource adminAiProjectAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: if (!empty(projectName)) {
  name: guid(resourceGroup().id, aiProject.id, admin.objectId, 'b78c5d69-af96-48a3-bf8d-a8b4d589de94')
  scope: aiProject
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b78c5d69-af96-48a3-bf8d-a8b4d589de94')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Virtual Machine Administrator Login (1c0163c0-47e6-4577-8991-ea5c82e286e4)
resource adminVmAdminLogin 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: if (!empty(vmName)) {
  name: guid(resourceGroup().id, vm.id, admin.objectId, '1c0163c0-47e6-4577-8991-ea5c82e286e4')
  scope: vm
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1c0163c0-47e6-4577-8991-ea5c82e286e4')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Log Analytics Contributor (92aaf0da-9dab-42b6-94a3-d43ce8d16293)
resource adminLawContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: if (!empty(logAnalyticsWorkspaceName)) {
  name: guid(resourceGroup().id, logAnalyticsWorkspace.id, admin.objectId, '92aaf0da-9dab-42b6-94a3-d43ce8d16293')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Monitoring Contributor (749f88d5-cbae-40b8-bcfc-e573ddc772fa)
resource adminMonitoringContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: if (!empty(logAnalyticsWorkspaceName)) {
  name: guid(resourceGroup().id, logAnalyticsWorkspace.id, admin.objectId, '749f88d5-cbae-40b8-bcfc-e573ddc772fa')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '749f88d5-cbae-40b8-bcfc-e573ddc772fa')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Resource Group Contributor (b24988ac-6180-42a0-ab88-20f7382dd24c)
resource adminRgContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: {
  name: guid(resourceGroup().id, admin.objectId, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Resource Group User Access Administrator (18d7d88d-d35e-4fb5-a5c3-7773c20a72d9)
resource adminRgUserAccessAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: {
  name: guid(resourceGroup().id, admin.objectId, '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// ---------------------------------------------------------------------------
// USER ROLE ASSIGNMENTS - Operate, use, modify, and view across all services
// ---------------------------------------------------------------------------

// Key Vault Secrets User (4633458b-17de-408a-b874-0445c86b69e6)
resource userKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: {
  name: guid(resourceGroup().id, keyVault.id, usr.objectId, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Key Vault Secrets Officer (b86a8fe4-44ce-4948-aee5-eccb2c155cd7)
resource userKeyVaultSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: {
  name: guid(resourceGroup().id, keyVault.id, usr.objectId, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Key Vault Reader (21090545-7ca7-4776-b22c-e363652d74d2)
resource userKeyVaultReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: {
  name: guid(resourceGroup().id, keyVault.id, usr.objectId, '21090545-7ca7-4776-b22c-e363652d74d2')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '21090545-7ca7-4776-b22c-e363652d74d2')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Cognitive Services OpenAI User (5e0bd9bd-7b93-4f28-af87-19fc36ad61bd)
resource userOpenAiUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: {
  name: guid(resourceGroup().id, openAiAccount.id, usr.objectId, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Cognitive Services User (a97b65f3-24c7-4388-baec-2e87135dc908)
resource userCognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: {
  name: guid(resourceGroup().id, openAiAccount.id, usr.objectId, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Storage Blob Data Contributor (ba92f5b4-2d11-453d-a403-e96b0029c9fe)
resource userStorageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: if (!empty(storageAccountName)) {
  name: guid(resourceGroup().id, storageAccount.id, usr.objectId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe-user')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Azure AI Developer (64702f94-c441-49e6-a78b-ef80e0188fee) on AI Hub
resource userAiHubDeveloper 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: if (!empty(hubName)) {
  name: guid(resourceGroup().id, aiHub.id, usr.objectId, '64702f94-c441-49e6-a78b-ef80e0188fee')
  scope: aiHub
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '64702f94-c441-49e6-a78b-ef80e0188fee')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// AzureML Data Scientist (f6c7c914-8db3-469d-8ca1-694a8f32e121) on AI Hub
resource userAiHubDataScientist 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: if (!empty(hubName)) {
  name: guid(resourceGroup().id, aiHub.id, usr.objectId, 'f6c7c914-8db3-469d-8ca1-694a8f32e121')
  scope: aiHub
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f6c7c914-8db3-469d-8ca1-694a8f32e121')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Azure AI Developer (64702f94-c441-49e6-a78b-ef80e0188fee) on AI Project
resource userAiProjectDeveloper 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: if (!empty(projectName)) {
  name: guid(resourceGroup().id, aiProject.id, usr.objectId, '64702f94-c441-49e6-a78b-ef80e0188fee')
  scope: aiProject
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '64702f94-c441-49e6-a78b-ef80e0188fee')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// AzureML Data Scientist (f6c7c914-8db3-469d-8ca1-694a8f32e121) on AI Project
resource userAiProjectDataScientist 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: if (!empty(projectName)) {
  name: guid(resourceGroup().id, aiProject.id, usr.objectId, 'f6c7c914-8db3-469d-8ca1-694a8f32e121')
  scope: aiProject
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f6c7c914-8db3-469d-8ca1-694a8f32e121')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Virtual Machine User Login (fb879df8-f326-4884-b1cf-06f3ad86be52)
resource userVmUserLogin 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: if (!empty(vmName)) {
  name: guid(resourceGroup().id, vm.id, usr.objectId, 'fb879df8-f326-4884-b1cf-06f3ad86be52')
  scope: vm
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'fb879df8-f326-4884-b1cf-06f3ad86be52')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Log Analytics Reader (73c42c96-874c-492b-b04d-ab87d138a893)
resource userLawReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: if (!empty(logAnalyticsWorkspaceName)) {
  name: guid(resourceGroup().id, logAnalyticsWorkspace.id, usr.objectId, '73c42c96-874c-492b-b04d-ab87d138a893')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Monitoring Reader (43d0d8ad-25c7-4714-9337-8ba259a9fe05)
resource userMonitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: if (!empty(logAnalyticsWorkspaceName)) {
  name: guid(resourceGroup().id, logAnalyticsWorkspace.id, usr.objectId, '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Resource Group Reader (acdd72a7-3385-48ef-bd42-f606fba81ae7)
resource userRgReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: {
  name: guid(resourceGroup().id, usr.objectId, 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]
