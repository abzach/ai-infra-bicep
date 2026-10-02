# Azure Cosmos DB

Deployed by [`bicep/modules/cosmosdb.bicep`](../bicep/modules/cosmosdb.bicep) and orchestrated by `bicep/templates/main.bicep` when `deployCosmosDb` is `true`. The account is configured for Azure Cosmos DB for NoSQL with environment-controlled free-tier entitlement, private networking, and manual provisioned throughput.

## Configuration

| Setting | Value | Reason |
|---|---|---|
| API | NoSQL (`GlobalDocumentDB`) | Document model for lightweight workflow state and application metadata. |
| Free tier | `cosmosDbFreeTierEnabled` from YAML | Enables the lifetime free-tier discount for eligible subscriptions; Internal subscriptions must set this to `false`. |
| Throughput model | Manual provisioned throughput | Matches the free-tier wording for provisioned RU/s. |
| Throughput | `cosmosDbThroughput` from YAML, default 400 RU/s, maximum 1000 RU/s | Keeps the default deployment within the free-tier allowance when the entitlement is enabled. |
| Storage target | Keep data within 25 GB | Matches the free-tier storage allowance for the eligible account. |
| Database | `cosmosDbDatabaseName`, default `appstate` | Shared database for app or agent state. |
| Container | `cosmosDbContainerName`, default `metadata` | Initial container for lightweight metadata documents. |
| Partition key | `cosmosDbPartitionKeyPath`, default `/pk` | Required for scalable NoSQL containers. |
| Public network access | Disabled | Keeps the data plane private to the VNet. |
| Local key authentication | Disabled | Enforces Microsoft Entra identity instead of account keys. |
| Data-plane role | Cosmos DB built-in data contributor for the shared managed identity | Allows managed-identity clients to read and write documents without keys. |

## Networking

`network.bicep` creates `privatelink.documents.azure.com` and links it to the VNet when `deployCosmosDb` is `true`. `main.bicep` then creates a Cosmos DB private endpoint in the `services` subnet with group ID `Sql`.

## Free-tier guardrails

The free-tier entitlement is per subscription, and only one Cosmos DB account can receive the discount. Keep `deployCosmosDb` enabled for only one environment in an eligible subscription unless you intentionally accept billing for additional accounts. Internal subscriptions do not support the entitlement and must set `cosmosDbFreeTierEnabled: false`. `scripts/config.ps1` rejects `cosmosDbThroughput` values above 1000 RU/s, and `scripts/scan.ps1` verifies the explicit free-tier setting, private networking, disabled local auth, and provisioned throughput bounds.

## Disabling this component

Set `deployCosmosDb: false` in the environment YAML to remove the Cosmos DB account, its private endpoint, and its private DNS zone on the next deploy.

## Cross-Codebase Links

- [Root README](../README.md)
- [Architecture Documentation Index](README.md)
- [Bicep Modules](../bicep/modules/README.md)
- [Environment Configuration](../variables/README.md)