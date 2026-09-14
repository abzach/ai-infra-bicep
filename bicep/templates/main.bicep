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

@description('Entra ID object IDs to grant Key Vault Administrator and Storage Blob Data Contributor. Supply one or more IDs.')
param adminObjectIds array

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
param capacityK int

@description('Model deployment name for GPT-4o mini (secondary).')
param secondaryModelDeploymentName string

@description('Model family name for the secondary deployment.')
param secondaryModelName string

@description('Model version for the secondary deployment.')
param secondaryModelVersion string

@description('Provisioning SKU for the secondary deployment.')
param secondaryModelSkuName string

@description('Tokens-per-minute capacity in thousands for the secondary deployment.')
param secondaryCapacityK int

@description('Local administrator username for the Windows jumpbox VM.')
param vmAdminUsername string

@secure()
@description('Local administrator password for the Windows jumpbox VM.')
param vmAdminPassword string

@description('IPv4 CIDRs allowed to access Key Vault public endpoint (for example: 203.0.113.10/32).')
param keyVaultIpAllowList array = []

@description('IPv4 CIDRs allowed to access Storage Account public endpoint (for example: 203.0.113.10/32).')
param storageIpAllowList array = []

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
param vmAutoShutdownTimeZone string = 'India Standard Time'

@description('Enable private endpoints for AI Hub and AI Project workspaces.')
param privateAiWorkspacesOnly bool = true

@description('VNet address space CIDR.')
param addressSpace string = '10.0.0.0/16'

@description('Storage account access tier.')
@allowed([
  'Cool'
  'Hot'
  'Premium'
])
param storageAccessTier string = 'Hot'

@description('Name of the blob container created in the storage account for app artifact uploads.')
param containerName string = 'chatapp'

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
    tags: effectiveTags
    vmName: vmName
    rdpAllowedIpCidrs: rdpAllowedIpCidrs
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

module storageModule '../modules/storageaccount.bicep' = {
  name: 'storageDeployment'
  scope: coreRg
  params: {
    storageAccountName: storageAccountName
    location: location
    skuName: skuName
    adminObjectIds: adminObjectIds
    subnetId: networkModule.outputs.servicesSubnetId
    allowedIpCidrs: storageIpAllowList
    accessTier: storageAccessTier
    containerName: containerName
    tags: effectiveTags
  }
}

module keyVaultModule '../modules/keyvault.bicep' = {
  name: 'keyVaultDeployment'
  scope: coreRg
  params: {
    keyVaultName: keyVaultName
    location: location
    adminObjectIds: adminObjectIds
    deployingObjectId: deployingObjectId
    deployingPrincipalType: deployingPrincipalType
    subnetId: networkModule.outputs.servicesSubnetId
    allowedIpCidrs: keyVaultIpAllowList
    tags: effectiveTags
  }
}

module lawModule '../modules/loganalytics.bicep' = {
  name: 'logAnalyticsDeployment'
  scope: coreRg
  params: {
    workspaceName: lawWorkspaceName
    location: location
    retentionInDays: logAnalyticsRetentionDays
    tags: effectiveTags
  }
}

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
    logAnalyticsWorkspaceResourceId: lawModule.outputs.id
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
    hubIdentityPrincipalId: hubManagedIdentityModule.outputs.principalId
    vmIdentityPrincipalId: vmManagedIdentityModule.outputs.principalId
  }
  dependsOn: [
    storageModule
    keyVaultModule
    openAiModule
  ]
}

module storagePrivateEndpointModule '../modules/privateendpoint.bicep' = {
  name: 'storagePrivateEndpointDeployment'
  scope: networkRg
  params: {
    privateEndpointName: '${storageAccountName}-blob-pe'
    location: location
    subnetId: networkModule.outputs.servicesSubnetId
    privateLinkServiceId: storageModule.outputs.id
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

module aiHubModule '../modules/aihub.bicep' = {
  name: 'aiHubDeployment'
  scope: coreRg
  params: {
    hubName: hubName
    location: location
    storageAccountResourceId: storageModule.outputs.id
    keyVaultResourceId: keyVaultModule.outputs.id
    openAiEndpoint: openAiModule.outputs.endpoint
    openAiResourceId: openAiModule.outputs.id
    identityId: hubManagedIdentityModule.outputs.id
    logAnalyticsWorkspaceResourceId: lawModule.outputs.id
    tags: effectiveTags
  }
}

module aiProjectModule '../modules/aiproject.bicep' = {
  name: 'aiProjectDeployment'
  scope: coreRg
  params: {
    projectName: projectName
    location: location
    hubResourceId: aiHubModule.outputs.id
    tags: effectiveTags
  }
}

module aiHubPrivateEndpointModule '../modules/privateendpoint.bicep' = if (privateAiWorkspacesOnly) {
  name: 'aiHubPrivateEndpointDeployment'
  scope: networkRg
  params: {
    privateEndpointName: '${hubName}-pe'
    location: location
    subnetId: networkModule.outputs.servicesSubnetId
    privateLinkServiceId: aiHubModule.outputs.id
    groupId: 'amlworkspace'
    dnsZoneId: networkModule.outputs.amlApiDnsZoneId
    tags: effectiveTags
  }
}

module vmModule '../modules/vm.bicep' = {
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
    useSpotVm: vmUseSpot
    spotMaxPrice: vmSpotMaxPrice
    autoShutdownEnabled: vmAutoShutdownEnabled
    autoShutdownTime: vmAutoShutdownTime
    autoShutdownTimeZone: vmAutoShutdownTimeZone
    tags: effectiveTags
  }
}

output keyVaultUri string = keyVaultModule.outputs.vaultUri
output openAiEndpoint string = openAiModule.outputs.endpoint
output deploymentName string = openAiModule.outputs.deploymentName
output secondaryDeploymentName string = openAiModule.outputs.secondaryDeploymentName
output hubName string = aiHubModule.outputs.name
output projectName string = aiProjectModule.outputs.name
output hubManagedIdentityId string = hubManagedIdentityModule.outputs.id
output hubManagedIdentityPrincipalId string = hubManagedIdentityModule.outputs.principalId
output hubManagedIdentityClientId string = hubManagedIdentityModule.outputs.clientId
output vmManagedIdentityId string = vmManagedIdentityModule.outputs.id
output vmManagedIdentityPrincipalId string = vmManagedIdentityModule.outputs.principalId
output vmManagedIdentityClientId string = vmManagedIdentityModule.outputs.clientId
output vnetId string = networkModule.outputs.id
output vmName string = vmModule.outputs.vmName
output vmPublicIpAddress string = networkModule.outputs.publicIpAddress
output storageAccountName string = storageModule.outputs.name
output logAnalyticsWorkspaceId string = lawModule.outputs.id
output logAnalyticsWorkspaceName string = lawModule.outputs.name
