metadata description = 'Windows 11 Enterprise jumpbox VM.'

@description('VM name.')
param vmName string

@description('Azure region.')
param location string

@description('User-managed identity resource ID.')
param identityId string

@description('NIC resource ID to attach as primary interface.')
param nicId string

@description('Local administrator username for the Windows VM.')
param adminUsername string = 'azureadmin'

@secure()
@description('Local administrator password for the Windows VM.')
param adminPassword string

@description('Azure VM size.')
param vmSize string = 'Standard_D2s_v5'

@description('Publisher of the Azure Marketplace VM image.')
param imagePublisher string = 'microsoftwindowsdesktop'

@description('Offer of the Azure Marketplace VM image.')
param imageOffer string = 'windows-ent-cpc'

@description('SKU of the Azure Marketplace VM image.')
param imageSku string = 'win11-24h2-ent'

@description('Version of the Azure Marketplace VM image.')
param imageVersion string = 'latest'

@description('Storage account type for the managed OS disk.')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param osDiskStorageAccountType string = 'Standard_LRS'

@description('Key Vault URI used by Azure Disk Encryption.')
param keyVaultUrl string

@description('Key Vault resource ID used by Azure Disk Encryption.')
param keyVaultResourceId string

@description('Use Spot VM priority to reduce costs when available.')
param useSpotVm bool = false

@description('Maximum hourly price for Spot VM. Use -1 to pay up to on-demand price.')
param spotMaxPrice int = -1

@description('Enable daily auto-shutdown schedule.')
param autoShutdownEnabled bool = true

@description('Daily auto-shutdown time in HHmm format.')
param autoShutdownTime string = '0300'

@description('Timezone for auto-shutdown schedule.')
param autoShutdownTimeZone string = 'UTC'

@description('Resource tags to apply.')
param tags object = {}

var osDiskName = '${vmName}-osdisk'
var computerName = length(vmName) > 15 ? substring(vmName, 0, 15) : vmName
var azureMonitorAgentSettings = {
  authentication: {
    managedIdentity: {
      'identifier-name': 'mi_res_id'
      'identifier-value': identityId
    }
  }
}
var antimalwareSettings = {
  AntimalwareEnabled: true
  RealtimeProtectionEnabled: true
  ScheduledScanSettings: {
    isEnabled: true
    day: 7
    time: 120
    scanType: 'Quick'
  }
}
var diskEncryptionSettings = {
  EncryptionOperation: 'EnableEncryption'
  KeyVaultURL: keyVaultUrl
  KeyVaultResourceId: keyVaultResourceId
  VolumeType: 'All'
}

resource vmSpot 'Microsoft.Compute/virtualMachines@2024-03-01' = if (useSpotVm) {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    priority: 'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: {
      maxPrice: spotMaxPrice
    }
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: imageVersion
      }
      osDisk: {
        name: osDiskName
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskStorageAccountType
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicId
          properties: {
            primary: true
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    licenseType: 'Windows_Client'
  }
}

resource vmRegular 'Microsoft.Compute/virtualMachines@2024-03-01' = if (!useSpotVm) {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: imageVersion
      }
      osDisk: {
        name: osDiskName
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskStorageAccountType
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicId
          properties: {
            primary: true
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    licenseType: 'Windows_Client'
  }
}

resource autoShutdownSchedule 'Microsoft.DevTestLab/schedules@2018-09-15' = if (autoShutdownEnabled) {
  name: 'shutdown-computevm-${vmName}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: autoShutdownTimeZone
    targetResourceId: useSpotVm ? vmSpot.id : vmRegular.id
    notificationSettings: {
      status: 'Disabled'
      timeInMinutes: 30
    }
  }
}

resource vmSpotAzureMonitorAgent 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = if (useSpotVm) {
  parent: vmSpot
  name: 'AzureMonitorWindowsAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: azureMonitorAgentSettings
  }
}

resource vmSpotAntimalware 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = if (useSpotVm) {
  parent: vmSpot
  name: 'IaaSAntimalware'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Security'
    type: 'IaaSAntimalware'
    typeHandlerVersion: '1.5'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: antimalwareSettings
  }
}

resource vmSpotDiskEncryption 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = if (useSpotVm) {
  parent: vmSpot
  name: 'AzureDiskEncryption'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Security'
    type: 'AzureDiskEncryption'
    typeHandlerVersion: '2.2'
    autoUpgradeMinorVersion: true
    settings: diskEncryptionSettings
  }
}

resource vmRegularAzureMonitorAgent 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = if (!useSpotVm) {
  parent: vmRegular
  name: 'AzureMonitorWindowsAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: azureMonitorAgentSettings
  }
}

resource vmRegularAntimalware 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = if (!useSpotVm) {
  parent: vmRegular
  name: 'IaaSAntimalware'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Security'
    type: 'IaaSAntimalware'
    typeHandlerVersion: '1.5'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: antimalwareSettings
  }
}

resource vmRegularDiskEncryption 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = if (!useSpotVm) {
  parent: vmRegular
  name: 'AzureDiskEncryption'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Security'
    type: 'AzureDiskEncryption'
    typeHandlerVersion: '2.2'
    autoUpgradeMinorVersion: true
    settings: diskEncryptionSettings
  }
}

output vmId string = useSpotVm ? vmSpot!.id : vmRegular!.id
output vmName string = useSpotVm ? vmSpot!.name : vmRegular!.name
output vmSize string = vmSize
output systemAssignedPrincipalId string = useSpotVm ? vmSpot!.identity.principalId : vmRegular!.identity.principalId
