metadata description = 'Azure Automation account, PowerShell runbooks, schedule, and VM-scoped RBAC.'

type runbookDescriptor = {
  name: string
  sourceHash: string
}

@description('Automation Account name.')
param automationAccountName string

@description('Azure region.')
param location string

@description('User-assigned managed identity resource ID.')
param identityId string

@description('User-assigned managed identity principal ID.')
param identityPrincipalId string

@description('PowerShell runtime version.')
param runtimeVersion string

@description('Az package version for the runtime environment.')
param azPackageVersion string

@description('Runbooks discovered from the repository automation folder.')
param runbooks runbookDescriptor[]

@description('Enable the daily VM start schedule.')
param vmStartScheduleEnabled bool

@description('VM start schedule name.')
param vmStartScheduleName string

@description('First occurrence of the VM start schedule.')
param vmStartScheduleStartTime string

@description('Time zone for the VM start schedule.')
param vmStartScheduleTimeZone string

@description('Enable the weekly temporary RDP deployer rule cleanup schedule.')
param rdpDeployerCleanupScheduleEnabled bool

@description('Temporary RDP deployer rule cleanup schedule name.')
param rdpDeployerCleanupScheduleName string

@description('First occurrence of the temporary RDP deployer rule cleanup schedule.')
param rdpDeployerCleanupScheduleStartTime string

@description('Time zone for the temporary RDP deployer rule cleanup schedule.')
param rdpDeployerCleanupScheduleTimeZone string

@description('VM resource ID used as the role assignment scope.')
param vmResourceId string

@description('Resource tags to apply.')
param tags object = {}

var runtimeEnvironmentName = 'PowerShell-${replace(runtimeVersion, '.', '-')}'
var startVmRunbookName = 'schedule-vm-start'
var deleteRdpDeployerRuleRunbookName = 'delete-nsg-rule'

resource automationAccount 'Microsoft.Automation/automationAccounts@2024-10-23' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    disableLocalAuth: true
    publicNetworkAccess: false
    sku: {
      name: 'Basic'
    }
  }
}

resource runtimeEnvironment 'Microsoft.Automation/automationAccounts/runtimeEnvironments@2024-10-23' = {
  parent: automationAccount
  name: runtimeEnvironmentName
  location: location
  properties: {
    description: 'Repository-managed PowerShell runtime.'
    runtime: {
      language: 'PowerShell'
      version: runtimeVersion
    }
    defaultPackages: {
      Az: azPackageVersion
    }
  }
}

resource automationRunbooks 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = [for runbook in runbooks: {
  parent: automationAccount
  name: runbook.name
  location: location
  tags: union(tags, {
    sourceHash: runbook.sourceHash
  })
  properties: {
    description: 'Published from automation/${runbook.name}.ps1.'
    logProgress: false
    logVerbose: true
    runbookType: 'PowerShell'
    runtimeEnvironment: runtimeEnvironment.name
  }
}]

resource vmStartSchedule 'Microsoft.Automation/automationAccounts/schedules@2024-10-23' = if (vmStartScheduleEnabled) {
  parent: automationAccount
  name: vmStartScheduleName
  properties: {
    description: 'Starts the environment VM every day.'
    frequency: 'Day'
    interval: 1
    startTime: vmStartScheduleStartTime
    timeZone: vmStartScheduleTimeZone
  }
}

resource rdpDeployerCleanupSchedule 'Microsoft.Automation/automationAccounts/schedules@2024-10-23' = if (rdpDeployerCleanupScheduleEnabled) {
  parent: automationAccount
  name: rdpDeployerCleanupScheduleName
  properties: {
    description: 'Deletes the temporary allow-rdp-deployer NSG rule once per week.'
    frequency: 'Week'
    interval: 1
    startTime: rdpDeployerCleanupScheduleStartTime
    timeZone: rdpDeployerCleanupScheduleTimeZone
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' existing = {
  name: last(split(vmResourceId, '/'))
}

resource automationVmContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vm.id, identityPrincipalId, '9980e02c-c2be-4d73-94e8-173b1dc7cf3c')
  scope: vm
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c')
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output accountName string = automationAccount.name
output runbookNames string[] = [for runbook in runbooks: runbook.name]
output scheduleName string = vmStartScheduleEnabled ? vmStartSchedule.name : ''
output jobScheduleName string = vmStartScheduleEnabled ? guid(automationAccount.id, startVmRunbookName, vmStartScheduleName) : ''
output rdpDeployerCleanupScheduleName string = rdpDeployerCleanupScheduleEnabled ? rdpDeployerCleanupSchedule.name : ''
output rdpDeployerCleanupJobScheduleName string = rdpDeployerCleanupScheduleEnabled ? guid(automationAccount.id, deleteRdpDeployerRuleRunbookName, rdpDeployerCleanupScheduleName) : ''
