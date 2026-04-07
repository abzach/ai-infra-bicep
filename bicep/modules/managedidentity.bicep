metadata description = 'User-assigned managed identity.'

@description('Managed identity name.')
param identityName string

@description('Azure region.')
param location string

@description('Resource tags to apply.')
param tags object = {}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

output id string = managedIdentity.id
output principalId string = managedIdentity.properties.principalId
output clientId string = managedIdentity.properties.clientId
