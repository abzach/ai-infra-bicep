metadata description = 'Azure OpenAI account with GPT-4.1 mini and GPT-4o mini deployments.'

@description('Azure OpenAI account name. Must be globally unique.')
param openAiAccountName string

@description('Azure region.')
param location string

@description('Deployment name for the primary model (GPT-4.1 mini).')
param modelDeploymentName string = 'gpt-4-1-mini'

@description('Model family name for the primary deployment (e.g. gpt-4.1-mini).')
param modelName string = 'gpt-4.1-mini'

@description('Model version for the primary deployment (e.g. 2025-04-14).')
param modelVersion string = '2025-04-14'

@description('Provisioning SKU for the primary deployment (e.g. GlobalStandard).')
param modelSkuName string = 'GlobalStandard'

@description('Tokens-per-minute capacity in thousands for the primary deployment.')
param capacityK int = 10

@description('Deployment name for the secondary model (GPT-4o mini).')
param secondaryModelDeploymentName string = 'gpt-4o-mini'

@description('Model family name for the secondary deployment (e.g. gpt-4o-mini).')
param secondaryModelName string = 'gpt-4o-mini'

@description('Model version for the secondary deployment (e.g. 2024-07-18).')
param secondaryModelVersion string = '2024-07-18'

@description('Provisioning SKU for the secondary deployment (e.g. GlobalStandard).')
param secondaryModelSkuName string = 'GlobalStandard'

@description('Tokens-per-minute capacity in thousands for the secondary deployment.')
param secondaryCapacityK int = 8

@description('Log Analytics workspace resource ID used for diagnostics.')
param logAnalyticsWorkspaceResourceId string

@description('Disable local authentication (API key access). Defaults to true to enforce Entra ID-only authentication.')
param disableLocalAuth bool = true

@description('Resource tags to apply.')
param tags object = {}

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiAccountName
  location: location
  tags: tags
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiAccountName
    disableLocalAuth: disableLocalAuth
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
}

resource openAiDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: openAiAccount
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

resource primaryModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiAccount
  name: modelDeploymentName
  sku: {
    name: modelSkuName
    capacity: capacityK
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

resource secondaryModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiAccount
  name: secondaryModelDeploymentName
  sku: {
    name: secondaryModelSkuName
    capacity: secondaryCapacityK
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: secondaryModelName
      version: secondaryModelVersion
    }
  }
  dependsOn: [primaryModelDeployment]
}

output id string = openAiAccount.id
output name string = openAiAccount.name
output endpoint string = openAiAccount.properties.endpoint
output deploymentName string = primaryModelDeployment.name
output secondaryDeploymentName string = secondaryModelDeployment.name
