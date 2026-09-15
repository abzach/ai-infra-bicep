metadata description = 'Storage account with private endpoint and RBAC.'

@description('Storage account name. Must be globally unique and 3-24 lowercase alphanumeric.')
param storageAccountName string

@description('Azure region.')
param location string

@description('Storage redundancy SKU.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
param skuName string = 'Standard_LRS'

@description('Object IDs of users that should receive Storage Blob Data Contributor on this account. Leave empty to skip.')
param adminObjectIds array = []

@description('Storage account access tier.')
@allowed([
  'Cool'
  'Hot'
])
param accessTier string = 'Hot'

@description('Name of the blob container to create for app artifact uploads.')
param containerName string = 'chatapp'

@description('Resource tags to apply.')
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  tags: tags
  properties: {
    accessTier: accessTier
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

@description('Blob soft delete retention in days. 0 disables soft delete.')
@minValue(0)
@maxValue(365)
param blobSoftDeleteRetentionDays int = 7

@description('Container soft delete retention in days. 0 disables soft delete.')
@minValue(0)
@maxValue(365)
param containerSoftDeleteRetentionDays int = 7

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: blobSoftDeleteRetentionDays > 0 ? {
      enabled: true
      days: max(blobSoftDeleteRetentionDays, 1)
    } : {
      enabled: false
    }
    containerDeleteRetentionPolicy: containerSoftDeleteRetentionDays > 0 ? {
      enabled: true
      days: max(containerSoftDeleteRetentionDays, 1)
    } : {
      enabled: false
    }
  }
}

resource chatAppContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

resource adminStorageBlobDataContributorRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for adminId in adminObjectIds: {
  name: guid(resourceGroup().id, storageAccount.id, adminId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe-admin')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: adminId
    principalType: 'User'
  }
}]

output id string = storageAccount.id
output name string = storageAccount.name
