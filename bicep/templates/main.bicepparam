using './main.bicep'

// Sample parameter file used for local `az bicep build-params` checks and Bicep MCP deployment
// snapshots only. deploy.ps1 never reads this file: it generates a parameter file from
// variables/core.yaml plus variables/<env>.yaml. Keep every value here generic — real
// environment values belong exclusively in the untracked variables/*.yaml files.

param adminActors = [
  {
    objectId: '00000000-0000-0000-0000-000000000000'
    principalType: 'User'
  }
]

param userActors = []

param environmentSuffix = 'dev'

param baseName = 'sample'
param location = 'eastus'
param skuName = 'Standard_LRS'

param deployStorage = true
param deployLogAnalytics = true
param deployAiFoundry = true
param deployVm = true
param deployAutomation = true

param storageAccessTier = 'Hot'
param containerName = 'chatapp'
param storageBlobSoftDeleteRetentionDays = 7
param storageContainerSoftDeleteRetentionDays = 7
param keyVaultSoftDeleteRetentionDays = 7

param modelDeployments = [
  {
    deploymentName: 'primary-model'
    modelName: 'gpt-4.1-mini'
    modelVersion: '2025-04-14'
    skuName: 'GlobalStandard'
    capacityK: 10
  }
  {
    deploymentName: 'secondary-model'
    modelName: 'gpt-4.1-nano'
    modelVersion: '2025-04-14'
    skuName: 'GlobalStandard'
    capacityK: 8
  }
]

param disableLocalAuth = true
param privateAiWorkspacesOnly = true

param addressSpace = '10.0.0.0/16'
param servicesSubnetAddressPrefix = '10.0.1.0/24'
param vmSubnetAddressPrefix = '10.0.2.0/24'
param vmAcceleratedNetworking = true
param vmPublicIpDnsNameLabel = ''
param rdpAllowRules = [
  {
    name: 'allow-rdp-user'
    sourceAddressPrefixes: [
      '203.0.113.10/32'
    ]
  }
]

param vmAdminUsername = 'azureadmin'
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')
param vmSize = 'Standard_D2s_v5'
param vmImagePublisher = 'microsoftwindowsdesktop'
param vmImageOffer = 'windows-ent-cpc'
param vmImageSku = 'win11-24h2-ent-cpc-m365'
param vmImageVersion = 'latest'
param vmOsDiskStorageAccountType = 'Standard_LRS'
param vmUseSpot = false
param vmSpotMaxPrice = -1
param vmAutoShutdownEnabled = true
param vmAutoShutdownTime = '0300'
param vmAutoShutdownTimeZone = 'UTC'
param automationRuntimeVersion = '7.4'
param automationAzVersion = '12.3.0'
param automationRunbooks = [
  {
    name: 'delete-rdp-deployer-rule'
    sourceHash: '0000000000000000000000000000000000000000000000000000000000000000'
  }
  {
    name: 'start-vm'
    sourceHash: '0000000000000000000000000000000000000000000000000000000000000000'
  }
]
param vmStartScheduleEnabled = true
param vmStartScheduleStartTime = '2026-12-01T11:00:00+00:00'
param vmStartScheduleTimeZone = 'Etc/UTC'
param rdpDeployerCleanupScheduleEnabled = true
param rdpDeployerCleanupScheduleStartTime = '2026-12-01T00:00:00+00:00'
param rdpDeployerCleanupScheduleTimeZone = 'Etc/UTC'
param nameSuffix = '0000'

param logAnalyticsRetentionDays = 30

param tags = {
  environment: 'dev'
  project: 'sample'
  workload: 'enterprise-ai-foundry'
  managedBy: 'bicep'
}
