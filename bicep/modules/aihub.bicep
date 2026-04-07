metadata description = 'AI Foundry hub with Azure OpenAI connection.'

@description('AI Hub workspace name.')
param hubName string

@description('Azure region.')
param location string

@description('Storage account resource ID used by AI Hub.')
param storageAccountResourceId string

@description('Key Vault resource ID used by AI Hub.')
param keyVaultResourceId string

@description('Azure OpenAI endpoint URL.')
param openAiEndpoint string

@description('Azure OpenAI account resource ID.')
param openAiResourceId string

@description('User-managed identity resource ID.')
param identityId string

@description('Log Analytics workspace resource ID used for diagnostics.')
param logAnalyticsWorkspaceResourceId string

@description('Resource tags to apply.')
param tags object = {}

resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: hubName
  location: location
  tags: tags
  kind: 'Hub'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  sku: {
    name: 'Basic'
  }
  properties: {
    storageAccount: storageAccountResourceId
    keyVault: keyVaultResourceId
    primaryUserAssignedIdentity: identityId
    publicNetworkAccess: 'Disabled'
    allowPublicAccessWhenBehindVnet: false
  }
}

resource openAiConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-10-01' = {
  parent: aiHub
  name: 'openai-connection'
  properties: {
    category: 'AzureOpenAI'
    target: openAiEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ApiVersion: '2024-10-01-preview'
      ResourceId: openAiResourceId
    }
  }
}

resource aiHubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: aiHub
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

output id string = aiHub.id
output name string = aiHub.name
// principalId is empty for hubs using UserAssigned-only identity (no system-assigned identity).
// Use managedIdentityModule.outputs.principalId from main.bicep when the identity principal is needed.
output principalId string = aiHub.identity.?principalId ?? ''
output identityId string = identityId
