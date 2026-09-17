metadata description = 'Azure OpenAI account with repository-configured model deployments.'

type modelDeploymentConfig = {
  @description('Deployment alias used by clients.')
  deploymentName: string
  @description('Exact model catalog name.')
  modelName: string
  @description('Exact model version.')
  modelVersion: string
  @description('Provisioning SKU supported by the model and region.')
  skuName: string
  @description('Tokens-per-minute capacity in thousands.')
  @minValue(1)
  capacityK: int
}

@description('Azure OpenAI account name. Must be globally unique.')
param openAiAccountName string

@description('Azure region.')
param location string

@description('One or more Azure OpenAI model deployments. The first two are exposed to the chat app as its primary and secondary models.')
@minLength(2)
param modelDeployments modelDeploymentConfig[]

@description('Log Analytics workspace resource ID used for diagnostics. Leave empty to skip diagnostic settings.')
param logAnalyticsWorkspaceResourceId string = ''

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

resource openAiDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceResourceId)) {
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

@batchSize(1)
resource modelDeploymentResources 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = [for modelDeployment in modelDeployments: {
  parent: openAiAccount
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
}]

output id string = openAiAccount.id
output name string = openAiAccount.name
output endpoint string = openAiAccount.properties.endpoint
output deploymentNames string[] = [for index in range(0, length(modelDeployments)): modelDeploymentResources[index].name]
output deploymentName string = modelDeploymentResources[0].name
output secondaryDeploymentName string = modelDeploymentResources[1].name
