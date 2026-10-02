metadata description = 'RBAC role assignments on the foundation resource group and its Foundry and VM resources for admin and user actors.'

type actorAssignment = {
  objectId: string
  principalType: ('User' | 'Group' | 'ServicePrincipal')?
}

@description('Array of administrator actors.')
param adminActors actorAssignment[] = []

@description('Array of user actors.')
param userActors actorAssignment[] = []

@description('Microsoft Foundry account name. Pass empty string if Foundry is not deployed.')
param foundryAccountName string = ''

@description('Microsoft Foundry child project name. Pass empty string if Foundry is not deployed.')
param foundryProjectName string = ''

@description('Jumpbox VM name. Pass empty string if VM is not deployed.')
param vmName string = ''

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: !empty(foundryAccountName) ? foundryAccountName : 'dummy-foundry'
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: foundryAccount
  name: !empty(foundryProjectName) ? foundryProjectName : 'dummy-project'
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' existing = {
  name: !empty(vmName) ? vmName : 'dummy-vm'
}

// Foundry Owner (c883944f-8b7b-4483-af10-35834be79c4a)
resource adminFoundryOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: if (!empty(foundryAccountName)) {
  name: guid(foundryAccount.id, admin.objectId, 'c883944f-8b7b-4483-af10-35834be79c4a')
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'c883944f-8b7b-4483-af10-35834be79c4a')
    principalId: admin.objectId
    principalType: admin.?principalType ?? 'User'
  }
}]

// Foundry Project Manager (eadc314b-1a2d-4efa-be10-5d325db5065e)
resource adminFoundryProjectManager 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (admin, i) in adminActors: if (!empty(foundryProjectName)) {
  name: guid(foundryProject.id, admin.objectId, 'eadc314b-1a2d-4efa-be10-5d325db5065e')
  scope: foundryProject
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'eadc314b-1a2d-4efa-be10-5d325db5065e')
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

// Foundry User (53ca6127-db72-4b80-b1b0-d745d6d5456d)
resource userFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: if (!empty(foundryProjectName)) {
  name: guid(foundryProject.id, usr.objectId, '53ca6127-db72-4b80-b1b0-d745d6d5456d')
  scope: foundryProject
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
    principalId: usr.objectId
    principalType: usr.?principalType ?? 'User'
  }
}]

// Foundry Agent Consumer (eed3b665-ab3a-47b6-8f48-c9382fb1dad6)
resource userFoundryAgentConsumer 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (usr, i) in userActors: if (!empty(foundryProjectName)) {
  name: guid(foundryProject.id, usr.objectId, 'eed3b665-ab3a-47b6-8f48-c9382fb1dad6')
  scope: foundryProject
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'eed3b665-ab3a-47b6-8f48-c9382fb1dad6')
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
