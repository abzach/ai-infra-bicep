@description('Private endpoint resource name.')
param privateEndpointName string

@description('Azure region.')
param location string

@description('Subnet resource ID where private endpoint NIC is created.')
param subnetId string

@description('Private Link target resource ID.')
param privateLinkServiceId string

@description('Private Link group ID for the target service.')
param groupId string

@description('Private DNS zone resource ID for zone group integration (optional).')
param dnsZoneId string = ''

@description('Private DNS zone resource IDs for services that require multiple zone registrations.')
param dnsZoneIds string[] = []

@description('Resource tags to apply.')
param tags object = {}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${privateEndpointName}-connection'
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: [
            groupId
          ]
        }
      }
    ]
  }
}

var effectiveDnsZoneIds = !empty(dnsZoneIds) ? dnsZoneIds : (!empty(dnsZoneId) ? [dnsZoneId] : [])

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = if (!empty(effectiveDnsZoneIds)) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (effectiveDnsZoneId, index) in effectiveDnsZoneIds: {
        name: 'zone-${index}'
        properties: {
          privateDnsZoneId: effectiveDnsZoneId
        }
    }]
  }
}

output id string = privateEndpoint.id
