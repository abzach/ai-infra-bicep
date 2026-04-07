using './main.bicep'

param adminObjectIds = ['00000000-0000-0000-0000-000000000000']

param environmentSuffix = 'dev'

param baseName = 'aistack'
param location = 'swedencentral'
param skuName = 'Standard_LRS'

param storageAccessTier = 'Hot'
param containerName = 'chatapp'

param modelDeploymentName = 'gpt-4-1-mini'
param modelName = 'gpt-4.1-mini'
param modelVersion = '2025-04-14'
param modelSkuName = 'GlobalStandard'
param capacityK = 10
param secondaryModelDeploymentName = 'gpt-4o-mini'
param secondaryModelName = 'gpt-4o-mini'
param secondaryModelVersion = '2024-07-18'
param secondaryModelSkuName = 'GlobalStandard'
param secondaryCapacityK = 8

param disableLocalAuth = true

param addressSpace = '10.0.0.0/16'

param vmAdminUsername = 'azureadmin'
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')
param vmUseSpot = false
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
