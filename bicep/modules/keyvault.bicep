metadata description = 'RBAC-enabled Key Vault with admin role assignment.'

@description('Key Vault name. Must be globally unique, 3-24 chars.')
param keyVaultName string

@description('Azure region.')
param location string

@description('Object IDs of users or service principals that should be Key Vault Administrators. Supply one or more Entra ID object IDs.')
@minLength(1)
param adminObjectIds array

@description('VNet subnet resource ID allowed by Key Vault firewall.')
param subnetId string = ''

@description('IPv4 CIDR ranges allowed by Key Vault firewall (for example: 203.0.113.10/32).')
param allowedIpCidrs array = []

@description('Resource tags to apply.')
param tags object = {}

@description('Object ID of the deploying identity (service principal or user). Granted Key Vault Secrets Officer so it can sync secrets during deployment. Leave empty to skip.')
param deployingObjectId string = ''

@description('Principal type for deployingObjectId (User, ServicePrincipal, or Group).')
param deployingPrincipalType string = 'ServicePrincipal'

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
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: [for cidr in allowedIpCidrs: {
        value: cidr
      }]
      virtualNetworkRules: subnetId == '' ? [] : [
        {
          id: subnetId
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
    accessPolicies: []
  }
}

resource keyVaultAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for adminId in adminObjectIds: {
  name: guid(resourceGroup().id, adminId, keyVault.id, '00482a5a-887f-4fb3-b363-3b7fe8e74483')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: adminId
    principalType: 'User'
  }
}]

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
