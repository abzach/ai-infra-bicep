using './main.bicep'

param adminObjectIds = ['00000000-0000-0000-0000-000000000000']

param environmentSuffix = 'dev'

param baseName = 'aistack'
param location = 'swedencentral'
param skuName = 'Standard_LRS'

param storageAccessTier = 'Hot'
param containerName = 'chatapp'
param storageBlobSoftDeleteRetentionDays = 7
param storageContainerSoftDeleteRetentionDays = 7
param keyVaultSoftDeleteRetentionDays = 7

param modelDeploymentName = 'gpt-4-1-mini'
param modelName = 'gpt-4.1-mini'
param modelVersion = '2025-04-14'
param modelSkuName = 'GlobalStandard'
param capacityK = 10
param secondaryModelDeploymentName = 'gpt-4-1-nano'
param secondaryModelName = 'gpt-4.1-nano'
param secondaryModelVersion = '2025-04-14'
param secondaryModelSkuName = 'GlobalStandard'
param secondaryCapacityK = 8

param disableLocalAuth = true
param privateAiWorkspacesOnly = true

param addressSpace = '10.0.0.0/16'
param servicesSubnetAddressPrefix = '10.0.1.0/24'
param vmSubnetAddressPrefix = '10.0.2.0/24'
param vmAcceleratedNetworking = true

param vmAdminUsername = 'azureadmin'
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')
param vmSize = 'Standard_L2as_v4'
param vmImagePublisher = 'microsoftwindowsdesktop'
param vmImageOffer = 'windows-ent-cpc'
param vmImageSku = 'win11-24h2-ent-cpc-m365'
param vmImageVersion = 'latest'
param vmOsDiskStorageAccountType = 'Standard_LRS'
param vmUseSpot = false
param vmSpotMaxPrice = -1
param vmAutoShutdownEnabled = true
param vmAutoShutdownTime = '0300'
param vmAutoShutdownTimeZone = 'India Standard Time'
param nameSuffix = '0000'

param logAnalyticsRetentionDays = 30

param tags = {
  environment: 'dev'
  project: 'aistack'
  workload: 'enterprise-ai-foundry'
  managedBy: 'bicep'
}
