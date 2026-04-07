metadata description = 'Log Analytics workspace for audit diagnostics.'

@description('Log Analytics workspace name.')
param workspaceName string

@description('Azure region.')
param location string

@description('Workspace retention in days. PerGB2018 SKU minimum is 30 days.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Resource tags to apply.')
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output id string = workspace.id
output name string = workspace.name
