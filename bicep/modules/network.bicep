metadata description = 'Virtual network, private DNS zones, and VM networking resources.'

type rdpAllowRuleConfig = {
  name: 'allow-rdp-deployer' | 'allow-rdp-user'
  sourceAddressPrefixes: string[]
}

@description('Virtual network name.')
param vnetName string

@description('Address space for the VNet.')
param addressSpace string = '10.0.0.0/16'

@description('Address prefix for the private endpoints and services subnet.')
param servicesSubnetAddressPrefix string = '10.0.1.0/24'

@description('Address prefix for the VM subnet.')
param vmSubnetAddressPrefix string = '10.0.2.0/24'

@description('Azure region.')
param location string

@description('Resource tags to apply.')
param tags object = {}

@description('VM name used as a prefix for network resource names.')
param vmName string

@description('Named RDP allow rules for the deployer and configured user addresses.')
param rdpAllowRules rdpAllowRuleConfig[] = []

@description('Enable accelerated networking on the VM network interface.')
param acceleratedNetworkingEnabled bool = true

@description('Deploy the VM-specific network resources (public IP, NSG, NIC). Set to false when the jumpbox VM is not deployed.')
param deployVmNetworking bool = true

@description('Optional DNS name label for the VM public IP. Leave empty to skip a public DNS name.')
param publicIpDnsNameLabel string = ''

@description('Automation managed identity principal ID granted Network Contributor on the jumpbox NSG. Leave empty to skip.')
param automationPrincipalId string = ''

var subnets = [
  {
    name: 'services'
    addressPrefix: servicesSubnetAddressPrefix
  }
  {
    name: 'vm'
    addressPrefix: vmSubnetAddressPrefix
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

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = if (deployVmNetworking && empty(publicIpDnsNameLabel)) {
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

resource publicIpWithDns 'Microsoft.Network/publicIPAddresses@2024-01-01' = if (deployVmNetworking && !empty(publicIpDnsNameLabel)) {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: publicIpDnsNameLabel
    }
  }
}

var rdpSecurityRules = [for (rule, i) in rdpAllowRules: {
  name: rule.name
  properties: {
    access: 'Allow'
    direction: 'Inbound'
    priority: 200 + i
    protocol: 'Tcp'
    sourceAddressPrefixes: rule.sourceAddressPrefixes
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

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-01-01' = if (deployVmNetworking) {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: concat(rdpSecurityRules, rdpDenyRule)
  }
}

resource automationNsgContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployVmNetworking && !empty(automationPrincipalId)) {
  name: guid(networkSecurityGroup!.id, automationPrincipalId, '4d97b98b-1d4f-4787-a291-c67834d212e7')
  scope: networkSecurityGroup
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
    principalId: automationPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = if (deployVmNetworking) {
  name: nicName
  location: location
  tags: tags
  properties: {
    enableAcceleratedNetworking: acceleratedNetworkingEnabled
    networkSecurityGroup: {
      id: networkSecurityGroup!.id
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[1].id
          }
          publicIPAddress: {
            id: empty(publicIpDnsNameLabel) ? publicIp!.id : publicIpWithDns!.id
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
output nicId string = deployVmNetworking ? nic!.id : ''
output nicName string = deployVmNetworking ? nic!.name : ''
output privateIp string = deployVmNetworking ? nic!.properties.ipConfigurations[0].properties.privateIPAddress : ''
output publicIpAddress string = deployVmNetworking ? (empty(publicIpDnsNameLabel) ? publicIp!.properties.ipAddress : publicIpWithDns!.properties.ipAddress) : ''
output publicIpFqdn string = deployVmNetworking && !empty(publicIpDnsNameLabel) ? publicIpWithDns!.properties.dnsSettings.fqdn : ''
