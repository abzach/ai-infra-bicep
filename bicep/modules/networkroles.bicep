metadata description = 'RBAC role assignments on the network resource group for admin and user actors.'

type actorAssignment = {
  objectId: string
  principalType: ('User' | 'Group' | 'ServicePrincipal')?
}

@description('Array of administrator actors.')
param adminActors actorAssignment[] = []

@description('Array of user actors.')
param userActors actorAssignment[] = []

// Resource Group Contributor for Admins (b24988ac-6180-42a0-ab88-20f7382dd24c)
resource adminNetworkRgContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: {
  name: guid(resourceGroup().id, admin.objectId, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Resource Group User Access Administrator for Admins (18d7d88d-d35e-4fb5-a5c3-7773c20a72d9)
resource adminNetworkRgUserAccessAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: {
  name: guid(resourceGroup().id, admin.objectId, '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Resource Group Reader for Users (acdd72a7-3385-48ef-bd42-f606fba81ae7)
resource userNetworkRgReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: {
  name: guid(resourceGroup().id, usr.objectId, 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]
