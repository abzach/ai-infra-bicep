metadata description = 'Virtual network, private DNS zones, and VM networking resources.'

@description('Virtual network name.')
param vnetName string

@description('Address space for the VNet.')
param addressSpace string = '10.0.0.0/16'

@description('Azure region.')
param location string

@description('Resource tags to apply.')
param tags object = {}

@description('VM name used as a prefix for network resource names.')
param vmName string

@description('IPv4 CIDRs allowed to RDP into the VM (for example: 203.0.113.10/32). Leave empty to block all RDP.')
param rdpAllowedIpCidrs array = []

var subnets = [
  {
    name: 'services'
    addressPrefix: '10.0.1.0/24'
  }
  {
    name: 'vm'
    addressPrefix: '10.0.2.0/24'
  }
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpace
      ]
    }
    subnets: [for subnet in subnets: {
      name: subnet.name
      properties: {
        addressPrefix: subnet.addressPrefix
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Enabled'
        serviceEndpoints: [
          {
            service: 'Microsoft.CognitiveServices'
          }
          {
            service: 'Microsoft.KeyVault'
          }
          {
            service: 'Microsoft.Storage'
          }
        ]
      }
    }]
  }
}

resource kvDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}

resource oaiDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.openai.azure.com'
  location: 'global'
}

resource storageDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
}

resource amlApiDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.api.azureml.ms'
  location: 'global'
}

resource kvDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: kvDnsZone
  name: 'vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource oaiDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: oaiDnsZone
  name: 'vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource storageDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: storageDnsZone
  name: 'vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource amlApiDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: amlApiDnsZone
  name: 'vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

var nicName      = '${vmName}-nic'
var publicIpName = '${vmName}-pip'
var nsgName      = '${vmName}-nsg'

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

var rdpAllowRules = [for (cidr, i) in rdpAllowedIpCidrs: {
  name: 'allow-rdp-from-${replace(replace(cidr, '.', '-'), '/', '-')}'
  properties: {
    access: 'Allow'
    direction: 'Inbound'
    priority: 200 + i
    protocol: 'Tcp'
    sourceAddressPrefix: cidr
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    destinationPortRange: '3389'
  }
}]

var rdpDenyRule = [
  {
    name: 'deny-rdp-all'
    properties: {
      access: 'Deny'
      direction: 'Inbound'
      priority: 4096
      protocol: 'Tcp'
      sourceAddressPrefix: '*'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '3389'
    }
  }
]

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: concat(rdpAllowRules, rdpDenyRule)
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[1].id
          }
          publicIPAddress: {
            id: publicIp.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

output id string = vnet.id
output name string = vnet.name
output servicesSubnetId string = vnet.properties.subnets[0].id
output vmSubnetId string = vnet.properties.subnets[1].id
output kvDnsZoneId string = kvDnsZone.id
output oaiDnsZoneId string = oaiDnsZone.id
output storageDnsZoneId string = storageDnsZone.id
output amlApiDnsZoneId string = amlApiDnsZone.id
output nicId string = nic.id
output nicName string = nic.name
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output publicIpAddress string = publicIp.properties.ipAddress
