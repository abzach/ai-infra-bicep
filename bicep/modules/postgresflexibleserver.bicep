metadata description = 'Azure Database for PostgreSQL Flexible Server sized to stay within the Azure free-tier allowance: Burstable B1ms, 32 GiB storage, HA disabled, VNet-integrated with no public endpoint.'

@description('PostgreSQL Flexible Server name. Must be globally unique.')
param serverName string

@description('Azure region.')
param location string

@description('Compute SKU name. Standard_B1ms keeps the server within the Azure free-tier compute allowance.')
param skuName string = 'Standard_B1ms'

@description('PostgreSQL major version.')
@allowed([
  '11'
  '12'
  '13'
  '14'
  '15'
  '16'
])
param postgresVersion string = '16'

@description('Storage size in GiB. 32 GiB keeps the server within the Azure free-tier storage allowance.')
param storageSizeGB int = 32

@description('Backup retention in days.')
@minValue(7)
@maxValue(35)
param backupRetentionDays int = 7

@description('Administrator login name for the flexible server.')
param administratorLogin string

@secure()
@description('Administrator login password for the flexible server.')
param administratorLoginPassword string

@description('Resource ID of the delegated subnet used for VNet integration.')
param delegatedSubnetResourceId string

@description('Resource ID of the private DNS zone used for VNet integration.')
param privateDnsZoneResourceId string

@description('Resource tags to apply.')
param tags object = {}

// VNet-integrated flexible server: no public endpoint, no private endpoint needed.
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
    // Locked to Burstable: the only tier eligible for the Azure free-tier compute allowance.
    tier: 'Burstable'
  }
  properties: {
    version: postgresVersion
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Disabled'
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: delegatedSubnetResourceId
      privateDnsZoneArmResourceId: privateDnsZoneResourceId
    }
  }
}

output id string = postgresServer.id
output name string = postgresServer.name
output fqdn string = postgresServer.properties.fullyQualifiedDomainName
