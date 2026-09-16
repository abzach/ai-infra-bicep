targetScope = 'subscription'

metadata description = 'Enterprise Azure AI Foundry baseline with OpenAI, private endpoints, and jumpbox VM.'

@description('Base name used in resource naming. Keep short to satisfy storage account limits.')
@maxLength(10)
param baseName string

@description('Environment suffix for isolation.')
@allowed([
  'dev'
  'uat'
])
param environmentSuffix string

@description('Azure region.')
param location string

@description('Storage redundancy SKU.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
param skuName string

type actorAssignment = {
  objectId: string
  principalType: ('User' | 'Group' | 'ServicePrincipal')?
}

@description('Administrator actors granted highest level data-plane and control-plane roles across all services.')
param adminActors actorAssignment[] = []

@description('User actors granted permissions to use, operate, modify, and view services.')
param userActors actorAssignment[] = []

@description('Legacy Entra ID object IDs. Maintained for backwards compatibility.')
param adminObjectIds array = []

@description('Object ID of the deploying identity (service principal or user). Granted Key Vault Secrets Officer so it can sync secrets during deployment. Leave empty to skip.')
param deployingObjectId string = ''

@description('Principal type for deployingObjectId. Use ServicePrincipal for pipeline SPs, User for interactive accounts.')
param deployingPrincipalType string = 'ServicePrincipal'

@description('Model deployment name for GPT-4.1 mini (primary).')
param modelDeploymentName string

@description('Model family name for the primary deployment.')
param modelName string

@description('Model version for the primary deployment.')
param modelVersion string

@description('Provisioning SKU for the primary deployment.')
param modelSkuName string

@description('Tokens-per-minute capacity in thousands for the primary deployment.')
@minValue(1)
param capacityK int

@description('Model deployment name for GPT-4.1 nano (secondary).')
param secondaryModelDeploymentName string

@description('Model family name for the secondary deployment.')
param secondaryModelName string

@description('Model version for the secondary deployment.')
param secondaryModelVersion string

@description('Provisioning SKU for the secondary deployment.')
param secondaryModelSkuName string

@description('Tokens-per-minute capacity in thousands for the secondary deployment.')
@minValue(1)
param secondaryCapacityK int

@description('Local administrator username for the Windows jumpbox VM.')
param vmAdminUsername string

@secure()
@description('Local administrator password for the Windows jumpbox VM.')
param vmAdminPassword string

@description('Azure VM size for the Windows jumpbox.')
param vmSize string

@description('Publisher of the Azure Marketplace VM image.')
param vmImagePublisher string

@description('Offer of the Azure Marketplace VM image.')
param vmImageOffer string

@description('SKU of the Azure Marketplace VM image.')
param vmImageSku string

@description('Version of the Azure Marketplace VM image.')
param vmImageVersion string

@description('Storage account type for the managed VM OS disk.')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param vmOsDiskStorageAccountType string

@description('IPv4 CIDRs allowed to RDP into the jumpbox VM (for example: 203.0.113.10/32). Leave empty to block all RDP.')
param rdpAllowedIpCidrs array = []

@description('4-character suffix derived from the subscription ID for globally unique resource names.')
@minLength(4)
@maxLength(4)
param nameSuffix string

@description('Resource tags to apply across all modules.')
param tags object

@description('Use Spot VM priority to reduce compute cost.')
param vmUseSpot bool = true

@description('Maximum hourly Spot VM price. Use -1 to pay up to on-demand rate.')
param vmSpotMaxPrice int = -1

@description('Enable daily auto-shutdown for the jumpbox VM.')
param vmAutoShutdownEnabled bool = true

@description('Daily VM auto-shutdown time in HHmm format.')
param vmAutoShutdownTime string = '0300'

@description('Timezone used by VM auto-shutdown.')
param vmAutoShutdownTimeZone string = 'UTC'

@description('Deploy the Storage account and its private endpoint. Set to false to remove them; required when deployAiFoundry is true.')
param deployStorage bool = true

@description('Deploy the Log Analytics workspace. Set to false to remove it; required when audit diagnostics are enabled.')
param deployLogAnalytics bool = true

@description('Deploy the AI Foundry hub, project, and hub private endpoint. Set to false to remove them.')
param deployAiFoundry bool = true

@description('Deploy the jumpbox VM and its NIC, public IP, NSG, and auto-shutdown schedule. Set to false to remove them.')
param deployVm bool = true

@description('Provision the Automation Account and repository runbooks. Requires deployVm because the runbook targets the jumpbox.')
param deployAutomation bool = true

@description('PowerShell runtime version for Automation runbooks.')
param automationRuntimeVersion string = '7.4'

@description('Az package version for the Automation runtime.')
param automationAzVersion string = '12.3.0'

@description('Runbooks discovered from the repository automation folder.')
param automationRunbooks array = []

@description('Enable the daily VM start schedule.')
param vmStartScheduleEnabled bool = true

@description('First occurrence of the VM start schedule.')
param vmStartScheduleStartTime string = ''

@description('Time zone for the VM start schedule.')
param vmStartScheduleTimeZone string = 'Etc/UTC'

@description('Enable private endpoints for AI Hub and AI Project workspaces.')
param privateAiWorkspacesOnly bool = true

@description('VNet address space CIDR.')
param addressSpace string = '10.0.0.0/16'

@description('Services subnet address prefix CIDR.')
param servicesSubnetAddressPrefix string = '10.0.1.0/24'

@description('VM subnet address prefix CIDR.')
param vmSubnetAddressPrefix string = '10.0.2.0/24'

@description('Enable accelerated networking on the VM NIC.')
param vmAcceleratedNetworking bool = true

@description('Optional DNS name label for the VM public IP. Leave empty to skip a public DNS name.')
param vmPublicIpDnsNameLabel string = ''

@description('Storage account access tier.')
@allowed([
  'Cool'
  'Hot'
])
param storageAccessTier string = 'Hot'

@description('Blob soft-delete retention in days. Set to 0 to disable.')
@minValue(0)
@maxValue(365)
param storageBlobSoftDeleteRetentionDays int = 7

@description('Container soft-delete retention in days. Set to 0 to disable.')
@minValue(0)
@maxValue(365)
param storageContainerSoftDeleteRetentionDays int = 7

@description('Name of the blob container created in the storage account for app artifact uploads.')
param containerName string = 'chatapp'

@description('Key Vault soft-delete retention in days.')
@minValue(7)
@maxValue(90)
param keyVaultSoftDeleteRetentionDays int = 7

@description('Disable local authentication (API key access) on the Azure OpenAI account. Defaults to true to enforce Entra ID-only authentication.')
param disableLocalAuth bool = true

@description('Log Analytics retention in days.')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('ISO date (yyyy-MM-dd) of the initial resource creation. Leave empty to default to the current deployment date. deploy.ps1 reads this from the existing resource group tag so it is preserved across redeployments.')
param resourceCreatedDate string = ''

@description('ISO date (yyyy-MM-dd) stamped on every resource as lastModifiedDate. Defaults to the current UTC deployment date via utcNow().')
param lastModifiedDate string = utcNow('yyyy-MM-dd')

// Derive the effective createdDate: preserve the original date if provided, otherwise
// treat this deployment as the first and use the current UTC date.
var effectiveCreatedDate = empty(resourceCreatedDate) ? lastModifiedDate : resourceCreatedDate

// Merge the caller-supplied tags with the two date stamps so that all resources
// automatically carry up-to-date createdDate and lastModifiedDate tags without
// requiring the caller to compute or hardcode dates.
var effectiveTags = union(tags, {
  createdDate: effectiveCreatedDate
  lastModifiedDate: lastModifiedDate
})

var coreResourceGroupName    = 'rg-${baseName}-core-${environmentSuffix}-${nameSuffix}'
var networkResourceGroupName = 'rg-${baseName}-network-${environmentSuffix}-${nameSuffix}'
var storageAccountName       = 'st${baseName}${environmentSuffix}${nameSuffix}'
var keyVaultName             = 'kv-${baseName}-${environmentSuffix}-${nameSuffix}'
var openAiAccountName        = 'oai-${baseName}-${environmentSuffix}-${nameSuffix}'
var hubName                  = 'hub-${baseName}-${environmentSuffix}-${nameSuffix}'
var projectName              = 'proj-${baseName}-${environmentSuffix}-${nameSuffix}'
var hubManagedIdentityName   = 'mi-${baseName}-hub-${environmentSuffix}-${nameSuffix}'
var vmManagedIdentityName    = 'mi-${baseName}-vm-${environmentSuffix}-${nameSuffix}'
var automationManagedIdentityName = 'mi-${baseName}-automation-${environmentSuffix}-${nameSuffix}'
var automationAccountName    = 'aa-${baseName}-${environmentSuffix}-${nameSuffix}'
var vmStartScheduleName      = 'start-vm-daily'
var vnetName                 = 'vnet-${baseName}-${environmentSuffix}-${nameSuffix}'
var vmName                   = 'vm-${baseName}-${environmentSuffix}-${nameSuffix}'
var lawWorkspaceName         = 'law-${baseName}-${environmentSuffix}-${nameSuffix}'
resource coreRg 'Microsoft.Resources/resourceGroups@2024-07-01' = {
  name: coreResourceGroupName
  location: location
  tags: effectiveTags
}

resource networkRg 'Microsoft.Resources/resourceGroups@2024-07-01' = {
  name: networkResourceGroupName
  location: location
  tags: effectiveTags
}

module networkModule '../modules/network.bicep' = {
  name: 'networkDeployment'
  scope: networkRg
  params: {
    vnetName: vnetName
    location: location
    addressSpace: addressSpace
    servicesSubnetAddressPrefix: servicesSubnetAddressPrefix
    vmSubnetAddressPrefix: vmSubnetAddressPrefix
    acceleratedNetworkingEnabled: vmAcceleratedNetworking
    tags: effectiveTags
    vmName: vmName
    rdpAllowedIpCidrs: rdpAllowedIpCidrs
    deployVmNetworking: deployVm
    publicIpDnsNameLabel: vmPublicIpDnsNameLabel
  }
}

module hubManagedIdentityModule '../modules/managedidentity.bicep' = {
  name: 'hubManagedIdentityDeployment'
  scope: coreRg
  params: {
    identityName: hubManagedIdentityName
    location: location
    tags: effectiveTags
  }
}

module vmManagedIdentityModule '../modules/managedidentity.bicep' = {
  name: 'vmManagedIdentityDeployment'
  scope: coreRg
  params: {
    identityName: vmManagedIdentityName
    location: location
    tags: effectiveTags
  }
}

module automationManagedIdentityModule '../modules/managedidentity.bicep' = if (deployAutomation) {
  name: 'automationManagedIdentityDeployment'
  scope: coreRg
  params: {
    identityName: automationManagedIdentityName
    location: location
    tags: effectiveTags
  }
}

var legacyAdminActors = [for id in adminObjectIds: {
  objectId: id
  principalType: 'User'
}]

var effectiveAdminActors = !empty(adminActors) ? adminActors : legacyAdminActors

module storageModule '../modules/storageaccount.bicep' = if (deployStorage) {
  name: 'storageDeployment'
  scope: coreRg
  params: {
    storageAccountName: storageAccountName
    location: location
    skuName: skuName
    accessTier: storageAccessTier
    containerName: containerName
    blobSoftDeleteRetentionDays: storageBlobSoftDeleteRetentionDays
    containerSoftDeleteRetentionDays: storageContainerSoftDeleteRetentionDays
    tags: effectiveTags
  }
}

module keyVaultModule '../modules/keyvault.bicep' = {
  name: 'keyVaultDeployment'
  scope: coreRg
  params: {
    keyVaultName: keyVaultName
    location: location
    deployingObjectId: deployingObjectId
    deployingPrincipalType: deployingPrincipalType
    softDeleteRetentionInDays: keyVaultSoftDeleteRetentionDays
    tags: effectiveTags
  }
}

module lawModule '../modules/loganalytics.bicep' = if (deployLogAnalytics) {
  name: 'logAnalyticsDeployment'
  scope: coreRg
  params: {
    workspaceName: lawWorkspaceName
    location: location
    retentionInDays: logAnalyticsRetentionDays
    tags: effectiveTags
  }
}

// Diagnostics are wired only when Log Analytics is deployed; an empty ID disables them in the modules.
var logAnalyticsWorkspaceResourceId = deployLogAnalytics ? lawModule!.outputs.id : ''

module openAiModule '../modules/openai.bicep' = {
  name: 'openAiDeployment'
  scope: coreRg
  params: {
    openAiAccountName: openAiAccountName
    location: location
    modelDeploymentName: modelDeploymentName
    modelName: modelName
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    capacityK: capacityK
    secondaryModelDeploymentName: secondaryModelDeploymentName
    secondaryModelName: secondaryModelName
    secondaryModelVersion: secondaryModelVersion
    secondaryModelSkuName: secondaryModelSkuName
    secondaryCapacityK: secondaryCapacityK
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    disableLocalAuth: disableLocalAuth
    tags: effectiveTags
  }
}

module managedIdentityRolesModule '../modules/managedidentityroles.bicep' = {
  name: 'managedIdentityRolesDeployment'
  scope: coreRg
  params: {
    storageAccountName: storageAccountName
    keyVaultName: keyVaultName
    openAiAccountName: openAiAccountName
    grantStorageRole: deployStorage
    hubIdentityPrincipalId: hubManagedIdentityModule.outputs.principalId
    vmIdentityPrincipalId: vmManagedIdentityModule.outputs.principalId
  }
  dependsOn: [
    storageModule
    keyVaultModule
    openAiModule
  ]
}

module storagePrivateEndpointModule '../modules/privateendpoint.bicep' = if (deployStorage) {
  name: 'storagePrivateEndpointDeployment'
  scope: networkRg
  params: {
    privateEndpointName: '${storageAccountName}-blob-pe'
    location: location
    subnetId: networkModule.outputs.servicesSubnetId
    privateLinkServiceId: storageModule!.outputs.id
    groupId: 'blob'
    dnsZoneId: networkModule.outputs.storageDnsZoneId
    tags: effectiveTags
  }
}

module keyVaultPrivateEndpointModule '../modules/privateendpoint.bicep' = {
  name: 'keyVaultPrivateEndpointDeployment'
  scope: networkRg
  params: {
    privateEndpointName: '${keyVaultName}-pe'
    location: location
    subnetId: networkModule.outputs.servicesSubnetId
    privateLinkServiceId: keyVaultModule.outputs.id
    groupId: 'vault'
    dnsZoneId: networkModule.outputs.kvDnsZoneId
    tags: effectiveTags
  }
}

module openAiPrivateEndpointModule '../modules/privateendpoint.bicep' = {
  name: 'openAiPrivateEndpointDeployment'
  scope: networkRg
  params: {
    privateEndpointName: '${openAiAccountName}-account-pe'
    location: location
    subnetId: networkModule.outputs.servicesSubnetId
    privateLinkServiceId: openAiModule.outputs.id
    groupId: 'account'
    dnsZoneId: networkModule.outputs.oaiDnsZoneId
    tags: effectiveTags
  }
}

module aiHubModule '../modules/aihub.bicep' = if (deployAiFoundry) {
  name: 'aiHubDeployment'
  scope: coreRg
  params: {
    hubName: hubName
    location: location
    storageAccountResourceId: deployStorage ? storageModule!.outputs.id : ''
    keyVaultResourceId: keyVaultModule.outputs.id
    openAiEndpoint: openAiModule.outputs.endpoint
    openAiResourceId: openAiModule.outputs.id
    identityId: hubManagedIdentityModule.outputs.id
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    tags: effectiveTags
  }
}

module aiProjectModule '../modules/aiproject.bicep' = if (deployAiFoundry) {
  name: 'aiProjectDeployment'
  scope: coreRg
  params: {
    projectName: projectName
    location: location
    hubResourceId: aiHubModule!.outputs.id
    tags: effectiveTags
  }
}

module aiHubPrivateEndpointModule '../modules/privateendpoint.bicep' = if (deployAiFoundry && privateAiWorkspacesOnly) {
  name: 'aiHubPrivateEndpointDeployment'
  scope: networkRg
  params: {
    privateEndpointName: '${hubName}-pe'
    location: location
    subnetId: networkModule.outputs.servicesSubnetId
    privateLinkServiceId: aiHubModule!.outputs.id
    groupId: 'amlworkspace'
    dnsZoneId: networkModule.outputs.amlApiDnsZoneId
    tags: effectiveTags
  }
}

module vmModule '../modules/vm.bicep' = if (deployVm) {
  name: 'vmDeployment'
  scope: coreRg
  params: {
    vmName: vmName
    location: location
    identityId: vmManagedIdentityModule.outputs.id
    nicId: networkModule.outputs.nicId
    keyVaultUrl: keyVaultModule.outputs.vaultUri
    keyVaultResourceId: keyVaultModule.outputs.id
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    vmSize: vmSize
    imagePublisher: vmImagePublisher
    imageOffer: vmImageOffer
    imageSku: vmImageSku
    imageVersion: vmImageVersion
    osDiskStorageAccountType: vmOsDiskStorageAccountType
    useSpotVm: vmUseSpot
    spotMaxPrice: vmSpotMaxPrice
    autoShutdownEnabled: vmAutoShutdownEnabled
    autoShutdownTime: vmAutoShutdownTime
    autoShutdownTimeZone: vmAutoShutdownTimeZone
    tags: effectiveTags
  }
}

module automationModule '../modules/automation.bicep' = if (deployAutomation) {
  name: 'automationDeployment'
  scope: coreRg
  params: {
    automationAccountName: automationAccountName
    location: location
    identityId: automationManagedIdentityModule!.outputs.id
    identityPrincipalId: automationManagedIdentityModule!.outputs.principalId
    runtimeVersion: automationRuntimeVersion
    azPackageVersion: automationAzVersion
    runbooks: automationRunbooks
    vmStartScheduleEnabled: vmStartScheduleEnabled
    vmStartScheduleName: vmStartScheduleName
    vmStartScheduleStartTime: vmStartScheduleStartTime
    vmStartScheduleTimeZone: vmStartScheduleTimeZone
    vmResourceId: vmModule!.outputs.vmId
    tags: effectiveTags
  }
}

module actorRolesModule '../modules/actorroles.bicep' = if (!empty(effectiveAdminActors) || !empty(userActors)) {
  name: 'actorRolesDeployment'
  scope: coreRg
  params: {
    adminActors: effectiveAdminActors
    userActors: userActors
    keyVaultName: keyVaultName
    openAiAccountName: openAiAccountName
    storageAccountName: deployStorage ? storageAccountName : ''
    hubName: deployAiFoundry ? hubName : ''
    projectName: deployAiFoundry ? projectName : ''
    vmName: deployVm ? vmName : ''
    logAnalyticsWorkspaceName: deployLogAnalytics ? lawWorkspaceName : ''
  }
  dependsOn: [
    keyVaultModule
    openAiModule
  ]
}

module networkRolesModule '../modules/networkroles.bicep' = if (!empty(effectiveAdminActors) || !empty(userActors)) {
  name: 'networkRolesDeployment'
  scope: networkRg
  params: {
    adminActors: effectiveAdminActors
    userActors: userActors
  }
  dependsOn: [
    networkModule
  ]
}

output keyVaultUri string = keyVaultModule.outputs.vaultUri
output openAiEndpoint string = openAiModule.outputs.endpoint
output deploymentName string = openAiModule.outputs.deploymentName
output secondaryDeploymentName string = openAiModule.outputs.secondaryDeploymentName
output hubName string = deployAiFoundry ? aiHubModule!.outputs.name : ''
output projectName string = deployAiFoundry ? aiProjectModule!.outputs.name : ''
output hubManagedIdentityId string = hubManagedIdentityModule.outputs.id
output hubManagedIdentityPrincipalId string = hubManagedIdentityModule.outputs.principalId
output hubManagedIdentityClientId string = hubManagedIdentityModule.outputs.clientId
output vmManagedIdentityId string = vmManagedIdentityModule.outputs.id
output vmManagedIdentityPrincipalId string = vmManagedIdentityModule.outputs.principalId
output vmManagedIdentityClientId string = vmManagedIdentityModule.outputs.clientId
output automationAccountName string = deployAutomation ? automationModule!.outputs.accountName : ''
output automationManagedIdentityId string = deployAutomation ? automationManagedIdentityModule!.outputs.id : ''
output automationManagedIdentityPrincipalId string = deployAutomation ? automationManagedIdentityModule!.outputs.principalId : ''
output automationManagedIdentityClientId string = deployAutomation ? automationManagedIdentityModule!.outputs.clientId : ''
output automationRunbookNames array = deployAutomation ? automationModule!.outputs.runbookNames : []
output vmStartScheduleName string = deployAutomation ? automationModule!.outputs.scheduleName : ''
output automationJobScheduleName string = deployAutomation ? automationModule!.outputs.jobScheduleName : ''
output vnetId string = networkModule.outputs.id
output vmName string = deployVm ? vmModule!.outputs.vmName : ''
output vmPublicIpAddress string = networkModule.outputs.publicIpAddress
output vmPublicIpFqdn string = networkModule.outputs.publicIpFqdn
output storageAccountName string = deployStorage ? storageModule!.outputs.name : ''
output logAnalyticsWorkspaceId string = logAnalyticsWorkspaceResourceId
output logAnalyticsWorkspaceName string = deployLogAnalytics ? lawModule!.outputs.name : ''
