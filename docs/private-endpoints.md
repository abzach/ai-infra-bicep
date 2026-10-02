# Private Endpoints & Private Link Integration

This document describes the private endpoint architecture provisioned by `bicep/modules/privateendpoint.bicep` and orchestrated in `bicep/templates/main.bicep`.

## Architecture Overview

All private Azure PaaS data-plane services in this architecture (Key Vault, Storage, Azure OpenAI, Microsoft Foundry, Azure AI Search, and Cosmos DB) have public network access disabled. They are accessed through private endpoints in the `services` subnet.

```
       Virtual Network (10.0.0.0/16)
       ├── VM Subnet (10.0.2.0/24)
       │     └── Jumpbox VM (10.0.2.4)
       │           │
       │           ▼
       └── Services Subnet (10.0.1.0/24)
             ├── Storage Blob PE ───► privatelink.blob.core.windows.net
             ├── Key Vault PE   ───► privatelink.vaultcore.azure.net
             ├── OpenAI PE      ───► privatelink.openai.azure.com
             ├── Foundry PE     ───► privatelink.services.ai.azure.com
             │                      privatelink.cognitiveservices.azure.com
             │                      privatelink.openai.azure.com
             ├── AI Search PE   ───► privatelink.search.windows.net
             └── Cosmos DB PE   ───► privatelink.documents.azure.com
```

## Private Endpoint Inventory

| Private Endpoint Name | Target Resource Type | Group ID (`groupId`) | Private DNS Zone Integrated | Subnet |
|---|---|---|---|---|
| `st<baseName><env><sfx>-blob-pe` | `Microsoft.Storage/storageAccounts` | `blob` | `privatelink.blob.core.windows.net` | `services` (`10.0.1.0/24`) |
| `kv-<baseName>-<env>-<sfx>-pe` | `Microsoft.KeyVault/vaults` | `vault` | `privatelink.vaultcore.azure.net` | `services` (`10.0.1.0/24`) |
| `oai-<baseName>-<env>-<sfx>-account-pe` | `Microsoft.CognitiveServices/accounts` | `account` | `privatelink.openai.azure.com` | `services` (`10.0.1.0/24`) |
| `ai-<baseName>-<env>-<sfx>-account-pe` | `Microsoft.CognitiveServices/accounts` | `account` | Foundry services, Cognitive Services, and OpenAI private zones | `services` (`10.0.1.0/24`) |
| `srch-<baseName>-<env>-<sfx>-search-pe` | `Microsoft.Search/searchServices` | `searchService` | `privatelink.search.windows.net` | `services` (`10.0.1.0/24`) |
| `cosmos-<baseName>-<env>-<sfx>-sql-pe` | `Microsoft.DocumentDB/databaseAccounts` | `Sql` | `privatelink.documents.azure.com` | `services` (`10.0.1.0/24`) |

## Important Configurations

| Property | Configured Value | Description |
|---|---|---|
| **Resource Type** | `Microsoft.Network/privateEndpoints@2024-01-01` | Private Endpoint provider API |
| **Subnet ID** | `networkModule.outputs.servicesSubnetId` | Subnet where private endpoint NICs are provisioned |
| **Private DNS Zone Group** | `default` / `default-zone` | Automatically creates DNS A-records in the corresponding Private DNS Zone |
| **Private Link Service Connection** | Named `<pe-name>-connection` | Establishes the Private Link connection to target PaaS service resource ID |

## Verification & Troubleshooting

- **DNS Resolution Check:** From inside the Jumpbox VM, execute `Resolve-DnsName <serviceName>.privatelink.openai.azure.com` or `Resolve-DnsName <vaultName>.privatelink.vaultcore.azure.net` to confirm they resolve to internal `10.0.1.x` addresses.
- **External Blocking Check:** Direct public access attempts from non-VNet IP addresses receive `403 Forbidden` / `Public network access is disabled`.

## Related Documentation

- [Virtual Network Documentation](virtual-network.md)
- [Key Vault Documentation](key-vault.md)
- [Storage Account Documentation](storage-account.md)
- [Azure OpenAI Documentation](azure-openai.md)
- [Microsoft Foundry Account](foundry-account.md)
- [Azure AI Search](ai-search.md)
- [Cosmos DB Documentation](cosmos-db.md)
- [Documentation Index](index.md)
