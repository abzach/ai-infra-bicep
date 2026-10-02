metadata description = 'Azure Cosmos DB for NoSQL account configured for the free-tier allowance with provisioned throughput and private networking.'

@description('Cosmos DB account name. Must be globally unique.')
param accountName string

@description('Azure region.')
param location string

@description('SQL database name.')
param databaseName string = 'appstate'

@description('SQL container name.')
param containerName string = 'metadata'

@description('Container partition key path.')
param partitionKeyPath string = '/pk'

@description('Manual provisioned database throughput in RU/s.')
@minValue(400)
@maxValue(1000)
param throughput int = 400

@description('Enable the Cosmos DB free-tier entitlement when supported by the subscription.')
param freeTierEnabled bool = true

@description('Principal ID of the shared managed identity granted Cosmos DB built-in data contributor access. Leave empty to skip data-plane RBAC.')
param sharedIdentityPrincipalId string = ''

@description('Resource tags to apply.')
param tags object = {}

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: freeTierEnabled
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    enableAutomaticFailover: false
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: account
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
    options: {
      throughput: throughput
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          partitionKeyPath
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
    }
  }
}

resource cosmosDataContributorRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2024-11-15' existing = {
  parent: account
  name: '00000000-0000-0000-0000-000000000002'
}

resource sharedIdentityCosmosDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = if (!empty(sharedIdentityPrincipalId)) {
  parent: account
  name: guid(account.id, sharedIdentityPrincipalId, cosmosDataContributorRole.id)
  properties: {
    principalId: sharedIdentityPrincipalId
    roleDefinitionId: cosmosDataContributorRole.id
    scope: account.id
  }
}

output id string = account.id
output name string = account.name
output endpoint string = account.properties.documentEndpoint
output databaseName string = database.name
output containerName string = container.name