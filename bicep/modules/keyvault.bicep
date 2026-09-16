metadata description = 'RBAC-enabled Key Vault with admin role assignment.'

@description('Key Vault name. Must be globally unique, 3-24 chars.')
param keyVaultName string

@description('Azure region.')
param location string

@description('Resource tags to apply.')
param tags object = {}

@description('Object ID of the deploying identity (service principal or user). Granted Key Vault Secrets Officer so it can sync secrets during deployment. Leave empty to skip.')
param deployingObjectId string = ''

@description('Principal type for deployingObjectId (User, ServicePrincipal, or Group).')
param deployingPrincipalType string = 'ServicePrincipal'

@description('Soft-delete retention in days. Azure allows 7-90 days and does not permit changing it after vault creation.')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 7

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enabledForDiskEncryption: true
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    accessPolicies: []
  }
}

resource keyVaultSecretsOfficerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployingObjectId)) {
  name: guid(resourceGroup().id, deployingObjectId, keyVault.id, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: deployingObjectId
    principalType: deployingPrincipalType
  }
}

output id string = keyVault.id
output name string = keyVault.name
output vaultUri string = keyVault.properties.vaultUri
