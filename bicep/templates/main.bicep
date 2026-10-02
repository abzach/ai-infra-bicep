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

type modelDeploymentConfig = {
  deploymentName: string
  modelName: string
  modelVersion: string
  skuName: string
  @minValue(1)
  capacityK: int
}

type rdpAllowRuleConfig = {
  name: 'allow-rdp-deployer' | 'allow-rdp-user'
  sourceAddressPrefixes: string[]
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

@description('Azure OpenAI model deployments. The first two are used by the chat app as primary and secondary models.')
@minLength(2)
param modelDeployments modelDeploymentConfig[]

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

@description('Named RDP allow rules for the deployer and configured user addresses.')
param rdpAllowRules rdpAllowRuleConfig[] = []

@description('4-character suffix derived from the subscription ID for globally unique resource names.')
@minLength(4)
@maxLength(4)
param nameSuffix string

@description('Instance number appended to resource group names, allowing multiple parallel instances per environment.')
param resourceGroupInstance string = '001'

@description('Resource ID of an existing managed disk to attach to the jumpbox VM instead of creating one from image. Used only for the one-time migration of a pre-existing VM disk; leave empty otherwise.')
param vmExistingOsDiskId string = ''

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

@description('Deploy the Azure Database for PostgreSQL Flexible Server, its delegated subnet, and its private DNS zone. Sized to the Azure free-tier allowance (Burstable B1ms, 32 GiB, HA disabled). Set to false to remove them.')
param deployPostgres bool = true

@description('Deploy Azure Static Web Apps on the Free hosting plan. Set to false to remove it.')
param deployStaticWebApp bool = true

@description('Azure region for Static Web Apps. Static Web Apps supports a subset of Azure regions.')
param staticWebAppLocation string = 'eastus2'

@description('Deploy Azure Cosmos DB for NoSQL with free tier enabled, provisioned throughput, and private endpoint. Set to false to remove it.')
param deployCosmosDb bool = true

@description('Deploy Azure API Management on the Consumption tier. Set to false to remove it.')
param deployApiManagement bool = true

@description('Deploy Azure App Service (Linux) on the F1 Free plan. Set to false to remove it.')
param deployAppService bool = true

@description('Address prefix for the PostgreSQL Flexible Server delegated subnet.')
param postgresSubnetAddressPrefix string = '10.0.3.0/24'

@description('PostgreSQL Flexible Server compute SKU name. Standard_B1ms keeps the server within the Azure free-tier compute allowance.')
param postgresSkuName string = 'Standard_B1ms'

@description('PostgreSQL major version.')
param postgresVersion string = '16'

@description('PostgreSQL Flexible Server storage size in GiB. 32 GiB keeps the server within the Azure free-tier storage allowance.')
param postgresStorageSizeGB int = 32

@description('PostgreSQL Flexible Server backup retention in days.')
@minValue(7)
@maxValue(35)
param postgresBackupRetentionDays int = 7

@description('PostgreSQL Flexible Server administrator login name.')
param postgresAdminUsername string = 'pgadmin'

@secure()
@description('PostgreSQL Flexible Server administrator login password.')
param postgresAdminPassword string = ''

@description('Static Web Apps SKU. Free keeps this component at the $0 plan target.')
@allowed([
  'Free'
])
param staticWebAppSkuName string = 'Free'

@description('Cosmos DB SQL database name.')
param cosmosDbDatabaseName string = 'appstate'

@description('Cosmos DB SQL container name.')
param cosmosDbContainerName string = 'metadata'

@description('Cosmos DB container partition key path.')
param cosmosDbPartitionKeyPath string = '/pk'

@description('Cosmos DB manual provisioned database throughput in RU/s. Keep at or below 1000 to stay within the free-tier throughput allowance.')
@minValue(400)
@maxValue(1000)
param cosmosDbThroughput int = 400

@description('Enable the Cosmos DB free-tier entitlement. Set to false for subscriptions that do not support Cosmos DB free tier, such as Internal subscriptions.')
param cosmosDbFreeTierEnabled bool = true

@description('API Management SKU. Consumption keeps this component on the serverless free-call allowance target.')
@allowed([
  'Consumption'
])
param apiManagementSkuName string = 'Consumption'

@description('API Management publisher contact email.')
param apiManagementPublisherEmail string = 'admin@example.com'

@description('API Management publisher display name.')
param apiManagementPublisherName string = 'AI Infra'

@description('App Service Plan SKU. F1 keeps this component at the $0 free-tier target.')
@allowed([
  'F1'
])
param appServiceSkuName string = 'F1'

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

@description('Enable the weekly temporary RDP deployer rule cleanup schedule.')
param rdpDeployerCleanupScheduleEnabled bool = true

@description('First occurrence of the temporary RDP deployer rule cleanup schedule.')
param rdpDeployerCleanupScheduleStartTime string = ''

@description('Time zone for the temporary RDP deployer rule cleanup schedule.')
param rdpDeployerCleanupScheduleTimeZone string = 'Etc/UTC'

@description('Enable the private endpoint for the Microsoft Foundry account.')
param privateAiWorkspacesOnly bool = true

@description('VNet address space CIDR.')
param addressSpace string = '10.0.0.0/16'

@description('Services subnet address prefix CIDR.')
param servicesSubnetAddressPrefix string = '10.0.1.0/24'

@description('VM subnet address prefix CIDR.')
param vmSubnetAddressPrefix string = '10.0.2.0/24'

@description('Dedicated Microsoft Foundry Agent Service subnet address prefix CIDR.')
param agentSubnetAddressPrefix string = '10.0.4.0/24'

@description('Optional replacement Agent Service subnet address prefix CIDR when the original subnet is still linked.')
param agentRecoverySubnetAddressPrefix string = ''

@description('Azure AI Search SKU used by Microsoft Foundry Agent Service.')
@allowed([
  'standard'
])
param aiSearchSkuName string = 'standard'

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

var workloadResourceGroupName    = 'rg-${baseName}-workload-${environmentSuffix}-${resourceGroupInstance}'
var foundationResourceGroupName  = 'rg-${baseName}-foundation-${environmentSuffix}-${resourceGroupInstance}'
var storageAccountName       = 'st${baseName}${environmentSuffix}${nameSuffix}${replace(resourceGroupInstance, '-', '')}'
var keyVaultName             = 'kv-${baseName}-${environmentSuffix}-${nameSuffix}-${resourceGroupInstance}'
var openAiAccountName        = 'oai-${baseName}-${environmentSuffix}-${nameSuffix}-${resourceGroupInstance}'
var foundryAccountName       = 'ai-${baseName}-${environmentSuffix}-${nameSuffix}-${resourceGroupInstance}'
var projectName              = 'proj-${baseName}-${environmentSuffix}-${resourceGroupInstance}'
var aiSearchName             = 'srch-${baseName}-${environmentSuffix}-${nameSuffix}-${resourceGroupInstance}'
var sharedManagedIdentityName = 'mi-${baseName}-${environmentSuffix}-${resourceGroupInstance}'
var automationAccountName    = 'aa-${baseName}-${environmentSuffix}-${resourceGroupInstance}'
var vmStartScheduleName      = 'schedule-vm-start-daily'
var rdpDeployerCleanupScheduleName = 'delete-rdp-deployer-weekly'
var vnetName                 = 'vnet-${baseName}-${environmentSuffix}-${resourceGroupInstance}'
var vmName                   = 'vm-${baseName}-${environmentSuffix}-${resourceGroupInstance}'
var lawWorkspaceName         = 'law-${baseName}-${environmentSuffix}-${resourceGroupInstance}'
var postgresServerName       = 'psql-${baseName}-${environmentSuffix}-${nameSuffix}-${resourceGroupInstance}'
var staticWebAppName         = 'stapp-${baseName}-${environmentSuffix}-${nameSuffix}-${resourceGroupInstance}'
var cosmosDbAccountName      = 'cosmos-${baseName}-${environmentSuffix}-${nameSuffix}-${resourceGroupInstance}'
var apiManagementServiceName = 'apim-${baseName}-${environmentSuffix}-${nameSuffix}-${resourceGroupInstance}'
var appServicePlanName        = 'asp-${baseName}-${environmentSuffix}-${resourceGroupInstance}'
var appServiceName           = 'web-${baseName}-${environmentSuffix}-${nameSuffix}-${resourceGroupInstance}'
resource workloadRg 'Microsoft.Resources/resourceGroups@2024-07-01' = {
  name: workloadResourceGroupName
  location: location
  tags: effectiveTags
}

resource foundationRg 'Microsoft.Resources/resourceGroups@2024-07-01' = {
  name: foundationResourceGroupName
  location: location
  tags: effectiveTags
}

module networkModule '../modules/network.bicep' = {
  name: 'networkDeployment'
  scope: foundationRg
  params: {
    vnetName: vnetName
    location: location
    addressSpace: addressSpace
    servicesSubnetAddressPrefix: servicesSubnetAddressPrefix
    vmSubnetAddressPrefix: vmSubnetAddressPrefix
    acceleratedNetworkingEnabled: vmAcceleratedNetworking
    tags: effectiveTags
    vmName: vmName
    rdpAllowRules: rdpAllowRules
    deployVmNetworking: deployVm
    publicIpDnsNameLabel: vmPublicIpDnsNameLabel
    automationPrincipalId: deployAutomation ? sharedManagedIdentityModule.outputs.principalId : ''
    deployPostgres: deployPostgres
    postgresSubnetAddressPrefix: postgresSubnetAddressPrefix
    deployCosmosDb: deployCosmosDb
    deployAiFoundry: deployAiFoundry
    agentSubnetAddressPrefix: agentSubnetAddressPrefix
    agentRecoverySubnetAddressPrefix: agentRecoverySubnetAddressPrefix
  }
}

module sharedManagedIdentityModule '../modules/managedidentity.bicep' = {
  name: 'sharedManagedIdentityDeployment'
  scope: foundationRg
  params: {
    identityName: sharedManagedIdentityName
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
  scope: workloadRg
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
  scope: workloadRg
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
  scope: workloadRg
  params: {
    workspaceName: lawWorkspaceName
    location: location
    retentionInDays: logAnalyticsRetentionDays
    tags: effectiveTags
  }
}

// Diagnostics are wired only when Log Analytics is deployed; an empty ID disables them in the modules.
var logAnalyticsWorkspaceResourceId = deployLogAnalytics ? lawModule!.outputs.id : ''

module postgresModule '../modules/postgresflexibleserver.bicep' = if (deployPostgres) {
  name: 'postgresDeployment'
  scope: workloadRg
  params: {
    serverName: postgresServerName
    location: location
    skuName: postgresSkuName
    postgresVersion: postgresVersion
    storageSizeGB: postgresStorageSizeGB
    backupRetentionDays: postgresBackupRetentionDays
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: postgresAdminPassword
    delegatedSubnetResourceId: networkModule.outputs.postgresSubnetId
    privateDnsZoneResourceId: networkModule.outputs.postgresDnsZoneId
    tags: effectiveTags
  }
}

module staticWebAppModule '../modules/staticwebapp.bicep' = if (deployStaticWebApp) {
  name: 'staticWebAppDeployment'
  scope: workloadRg
  params: {
    staticWebAppName: staticWebAppName
    location: staticWebAppLocation
    skuName: staticWebAppSkuName
    tags: effectiveTags
  }
}

module cosmosDbModule '../modules/cosmosdb.bicep' = if (deployCosmosDb) {
  name: 'cosmosDbDeployment'
  scope: workloadRg
  params: {
    accountName: cosmosDbAccountName
    location: location
    databaseName: cosmosDbDatabaseName
    containerName: cosmosDbContainerName
    partitionKeyPath: cosmosDbPartitionKeyPath
    throughput: cosmosDbThroughput
    freeTierEnabled: cosmosDbFreeTierEnabled
    sharedIdentityPrincipalId: sharedManagedIdentityModule.outputs.principalId
    tags: effectiveTags
  }
}

module aiSearchModule '../modules/aisearch.bicep' = if (deployAiFoundry) {
  name: 'aiSearchDeployment'
  scope: workloadRg
  params: {
    searchServiceName: aiSearchName
    location: location
    skuName: aiSearchSkuName
    tags: effectiveTags
  }
}

module apiManagementModule '../modules/apimanagement.bicep' = if (deployApiManagement) {
  name: 'apiManagementDeployment'
  scope: foundationRg
  params: {
    serviceName: apiManagementServiceName
    location: location
    skuName: apiManagementSkuName
    publisherEmail: apiManagementPublisherEmail
    publisherName: apiManagementPublisherName
    tags: effectiveTags
  }
}

module appServiceModule '../modules/appservice.bicep' = if (deployAppService) {
  name: 'appServiceDeployment'
  scope: foundationRg
  params: {
    appServicePlanName: appServicePlanName
    appServiceName: appServiceName
    location: location
    skuName: appServiceSkuName
    tags: effectiveTags
  }
}

module openAiModule '../modules/openai.bicep' = {
  name: 'openAiDeployment'
  scope: workloadRg
  params: {
    openAiAccountName: openAiAccountName
    location: location
    modelDeployments: modelDeployments
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    disableLocalAuth: disableLocalAuth
    tags: effectiveTags
  }
}

module managedIdentityRolesModule '../modules/managedidentityroles.bicep' = {
  name: 'managedIdentityRolesDeployment'
  scope: workloadRg
  params: {
    storageAccountName: storageAccountName
    keyVaultName: keyVaultName
    openAiAccountName: openAiAccountName
    grantStorageRole: deployStorage
    sharedIdentityPrincipalId: sharedManagedIdentityModule.outputs.principalId
  }
  dependsOn: [
    storageModule
    keyVaultModule
    openAiModule
  ]
}

module storagePrivateEndpointModule '../modules/privateendpoint.bicep' = if (deployStorage) {
  name: 'storagePrivateEndpointDeployment'
  scope: foundationRg
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
  scope: foundationRg
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
  scope: foundationRg
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

module cosmosDbPrivateEndpointModule '../modules/privateendpoint.bicep' = if (deployCosmosDb) {
  name: 'cosmosDbPrivateEndpointDeployment'
  scope: foundationRg
  params: {
    privateEndpointName: '${cosmosDbAccountName}-sql-pe'
    location: location
    subnetId: networkModule.outputs.servicesSubnetId
    privateLinkServiceId: cosmosDbModule!.outputs.id
    groupId: 'Sql'
    dnsZoneId: networkModule.outputs.cosmosDbDnsZoneId
    tags: effectiveTags
  }
}

module foundryModule '../modules/foundry.bicep' = if (deployAiFoundry) {
  name: 'foundryDeployment'
  scope: foundationRg
  params: {
    accountName: foundryAccountName
    projectName: projectName
    location: location
    agentSubnetId: networkModule.outputs.agentSubnetId
    storageAccountResourceId: deployStorage ? storageModule!.outputs.id : ''
    storageBlobEndpoint: deployStorage ? storageModule!.outputs.blobEndpoint : ''
    cosmosDbAccountResourceId: deployCosmosDb ? cosmosDbModule!.outputs.id : ''
    cosmosDbEndpoint: deployCosmosDb ? cosmosDbModule!.outputs.endpoint : ''
    aiSearchResourceId: aiSearchModule!.outputs.id
    aiSearchEndpoint: aiSearchModule!.outputs.endpoint
    modelDeployments: modelDeployments
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    tags: effectiveTags
  }
  dependsOn: [
    storagePrivateEndpointModule
    cosmosDbPrivateEndpointModule
  ]
}

module foundryPrivateEndpointModule '../modules/privateendpoint.bicep' = if (deployAiFoundry && privateAiWorkspacesOnly) {
  name: 'foundryPrivateEndpointDeployment'
  scope: foundationRg
  params: {
    privateEndpointName: '${foundryAccountName}-account-pe'
    location: location
    subnetId: networkModule.outputs.servicesSubnetId
    privateLinkServiceId: foundryModule!.outputs.accountId
    groupId: 'account'
    dnsZoneIds: [
      networkModule.outputs.aiServicesDnsZoneId
      networkModule.outputs.cognitiveServicesDnsZoneId
      networkModule.outputs.oaiDnsZoneId
    ]
    tags: effectiveTags
  }
}

module aiSearchPrivateEndpointModule '../modules/privateendpoint.bicep' = if (deployAiFoundry) {
  name: 'aiSearchPrivateEndpointDeployment'
  scope: foundationRg
  params: {
    privateEndpointName: '${aiSearchName}-search-pe'
    location: location
    subnetId: networkModule.outputs.servicesSubnetId
    privateLinkServiceId: aiSearchModule!.outputs.id
    groupId: 'searchService'
    dnsZoneId: networkModule.outputs.aiSearchDnsZoneId
    tags: effectiveTags
  }
}

module foundryRolesModule '../modules/foundryroles.bicep' = if (deployAiFoundry) {
  name: 'foundryRolesDeployment'
  scope: workloadRg
  params: {
    storageAccountName: storageAccountName
    cosmosDbAccountName: cosmosDbAccountName
    aiSearchName: aiSearchName
    projectPrincipalId: foundryModule!.outputs.projectPrincipalId
  }
}

module foundryCapabilityHostModule '../modules/foundrycapabilityhost.bicep' = if (deployAiFoundry) {
  name: 'foundryCapabilityHostDeployment'
  scope: foundationRg
  params: {
    accountName: foundryAccountName
    projectName: projectName
    storageConnectionName: foundryModule!.outputs.storageConnectionName
    cosmosDbConnectionName: foundryModule!.outputs.cosmosDbConnectionName
    aiSearchConnectionName: foundryModule!.outputs.aiSearchConnectionName
  }
  dependsOn: [
    foundryRolesModule
    foundryPrivateEndpointModule
    aiSearchPrivateEndpointModule
  ]
}

module vmModule '../modules/vm.bicep' = if (deployVm) {
  name: 'vmDeployment'
  scope: foundationRg
  params: {
    vmName: vmName
    location: location
    identityId: sharedManagedIdentityModule.outputs.id
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
    existingOsDiskId: vmExistingOsDiskId
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
  scope: foundationRg
  params: {
    automationAccountName: automationAccountName
    location: location
    identityId: sharedManagedIdentityModule.outputs.id
    identityPrincipalId: sharedManagedIdentityModule.outputs.principalId
    runtimeVersion: automationRuntimeVersion
    azPackageVersion: automationAzVersion
    runbooks: automationRunbooks
    vmStartScheduleEnabled: vmStartScheduleEnabled
    vmStartScheduleName: vmStartScheduleName
    vmStartScheduleStartTime: vmStartScheduleStartTime
    vmStartScheduleTimeZone: vmStartScheduleTimeZone
    rdpDeployerCleanupScheduleEnabled: rdpDeployerCleanupScheduleEnabled
    rdpDeployerCleanupScheduleName: rdpDeployerCleanupScheduleName
    rdpDeployerCleanupScheduleStartTime: rdpDeployerCleanupScheduleStartTime
    rdpDeployerCleanupScheduleTimeZone: rdpDeployerCleanupScheduleTimeZone
    vmResourceId: vmModule!.outputs.vmId
    tags: effectiveTags
  }
}

module actorRolesModule '../modules/actorroles.bicep' = if (!empty(effectiveAdminActors) || !empty(userActors)) {
  name: 'actorRolesDeployment'
  scope: workloadRg
  params: {
    adminActors: effectiveAdminActors
    userActors: userActors
    keyVaultName: keyVaultName
    openAiAccountName: openAiAccountName
    storageAccountName: deployStorage ? storageAccountName : ''
    hubName: ''
    projectName: ''
    logAnalyticsWorkspaceName: deployLogAnalytics ? lawWorkspaceName : ''
  }
  dependsOn: [
    keyVaultModule
    openAiModule
    storageModule
    lawModule
  ]
}

module networkRolesModule '../modules/networkroles.bicep' = if (!empty(effectiveAdminActors) || !empty(userActors)) {
  name: 'networkRolesDeployment'
  scope: foundationRg
  params: {
    adminActors: effectiveAdminActors
    userActors: userActors
    foundryAccountName: deployAiFoundry ? foundryAccountName : ''
    foundryProjectName: deployAiFoundry ? projectName : ''
    vmName: deployVm ? vmName : ''
  }
  dependsOn: [
    networkModule
    foundryModule
    vmModule
  ]
}

output keyVaultUri string = keyVaultModule.outputs.vaultUri
output openAiEndpoint string = openAiModule.outputs.endpoint
output deploymentName string = openAiModule.outputs.deploymentName
output secondaryDeploymentName string = openAiModule.outputs.secondaryDeploymentName
output foundryAccountName string = deployAiFoundry ? foundryModule!.outputs.accountName : ''
output foundryAccountEndpoint string = deployAiFoundry ? foundryModule!.outputs.accountEndpoint : ''
output projectName string = deployAiFoundry ? foundryModule!.outputs.projectName : ''
output foundryCapabilityHostName string = deployAiFoundry ? foundryCapabilityHostModule!.outputs.name : ''
output aiSearchName string = deployAiFoundry ? aiSearchModule!.outputs.name : ''
output sharedManagedIdentityId string = sharedManagedIdentityModule.outputs.id
output sharedManagedIdentityPrincipalId string = sharedManagedIdentityModule.outputs.principalId
output sharedManagedIdentityClientId string = sharedManagedIdentityModule.outputs.clientId
output automationAccountName string = deployAutomation ? automationModule!.outputs.accountName : ''
output automationRunbookNames array = deployAutomation ? automationModule!.outputs.runbookNames : []
output vmStartScheduleName string = deployAutomation ? automationModule!.outputs.scheduleName : ''
output automationJobScheduleName string = deployAutomation ? automationModule!.outputs.jobScheduleName : ''
output rdpDeployerCleanupScheduleName string = deployAutomation ? automationModule!.outputs.rdpDeployerCleanupScheduleName : ''
output rdpDeployerCleanupJobScheduleName string = deployAutomation ? automationModule!.outputs.rdpDeployerCleanupJobScheduleName : ''
output vnetId string = networkModule.outputs.id
output vmName string = deployVm ? vmModule!.outputs.vmName : ''
output vmPublicIpAddress string = networkModule.outputs.publicIpAddress
output vmPublicIpFqdn string = networkModule.outputs.publicIpFqdn
output storageAccountName string = deployStorage ? storageModule!.outputs.name : ''
output logAnalyticsWorkspaceId string = logAnalyticsWorkspaceResourceId
output logAnalyticsWorkspaceName string = deployLogAnalytics ? lawModule!.outputs.name : ''
output postgresServerName string = deployPostgres ? postgresModule!.outputs.name : ''
output postgresServerFqdn string = deployPostgres ? postgresModule!.outputs.fqdn : ''
output staticWebAppName string = deployStaticWebApp ? staticWebAppModule!.outputs.name : ''
output cosmosDbAccountName string = deployCosmosDb ? cosmosDbModule!.outputs.name : ''
output cosmosDbDatabaseName string = deployCosmosDb ? cosmosDbModule!.outputs.databaseName : ''
output cosmosDbContainerName string = deployCosmosDb ? cosmosDbModule!.outputs.containerName : ''
output apiManagementServiceName string = deployApiManagement ? apiManagementModule!.outputs.name : ''
output appServiceName string = deployAppService ? appServiceModule!.outputs.name : ''
