# Resource Groups

This document describes the dual Resource Group architecture deployed at subscription scope by `bicep/templates/main.bicep`.

## Architecture & Responsibilities

The deployment splits infrastructure into two distinct resource groups to separate core application/AI services from networking and security perimeter resources:

1. **Core Resource Group (`rg-<baseName>-core-<environmentSuffix>-<nameSuffix>`):** Hosts AI compute, AI Foundry Hub and Project workspaces, Key Vault, Storage Account, Managed Identities, Log Analytics, and Jumpbox VM.
2. **Network Resource Group (`rg-<baseName>-network-<environmentSuffix>-<nameSuffix>`):** Hosts the Virtual Network, subnets, Network Security Group, Public IP, Private DNS Zones, and all service Private Endpoints.

```
Subscription
  ├── rg-<baseName>-core-<env>-<suffix>
  │     ├── aiHub (Microsoft.MachineLearningServices/workspaces)
  │     ├── aiProject (Microsoft.MachineLearningServices/workspaces)
  │     ├── openAiAccount (Microsoft.CognitiveServices/accounts)
  │     ├── keyVault (Microsoft.KeyVault/vaults)
  │     ├── storageAccount (Microsoft.Storage/storageAccounts)
  │     ├── logAnalytics (Microsoft.OperationalInsights/workspaces)
  │     ├── vm (Microsoft.Compute/virtualMachines)
  │     └── userAssignedIdentities (Hub & VM)
  └── rg-<baseName>-network-<env>-<suffix>
        ├── vnet (Microsoft.Network/virtualNetworks)
        ├── nsg (Microsoft.Network/networkSecurityGroups)
        ├── publicIp (Microsoft.Network/publicIPAddresses)
        ├── nic (Microsoft.Network/networkInterfaces)
        ├── privateDnsZones (KV, OpenAI, Blob, AzureML)
        └── privateEndpoints (Storage, KV, OpenAI, AI Hub)
```

## Template Configuration

| Resource Name Pattern | Resource Type | Target Scope | Description |
|---|---|---|---|
| `rg-<baseName>-core-<env>-<suffix>` | `Microsoft.Resources/resourceGroups@2024-07-01` | Subscription | Core application, data, compute, and AI services resource group |
| `rg-<baseName>-network-<env>-<suffix>` | `Microsoft.Resources/resourceGroups@2024-07-01` | Subscription | Network isolation, private DNS, and private endpoint perimeter |

### Tagging Strategy

Every resource group and child resource inherits unified metadata tags configured via `variables/core.yaml` and environment overrides:

| Tag Key | Example Value | Description |
|---|---|---|
| `project` | `tagProject` from `variables/core.yaml` | Identifying project name |
| `workload` | `enterprise-ai-foundry` | Workload category used by cleanup validation |
| `environment` | `dev` / `uat` | Target environment identifier |
| `managedBy` | `bicep` | Deployment tool provenance |
| `createdDate` | `2026-09-16` | Initial creation ISO date (preserved across redeployments) |
| `lastModifiedDate` | `2026-09-16` | Dynamic UTC ISO date of latest deployment run |

## Related Documentation

- [Virtual Network Documentation](virtual-network.md)
- [Key Vault Documentation](key-vault.md)
- [Storage Account Documentation](storage-account.md)
- [Azure OpenAI Documentation](azure-openai.md)
- [Documentation Index](index.md)
