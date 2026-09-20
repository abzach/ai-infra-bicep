# Resource Groups

This document describes the dual Resource Group architecture deployed at subscription scope by `bicep/templates/main.bicep`.

## Architecture & Responsibilities

The deployment splits infrastructure into two distinct resource groups: one for workload-facing application/AI services and their globally-unique-named data, and one for networking, security perimeter, and the shared identity:

1. **Workload Resource Group (`rg-<baseName>-workload-<environmentSuffix>-<resourceGroupInstance>`):** Hosts the AI Foundry Hub and Project workspaces, Azure OpenAI, Key Vault, Storage Account, Log Analytics, the Automation Account, and the Jumpbox VM.
2. **Foundation Resource Group (`rg-<baseName>-foundation-<environmentSuffix>-<resourceGroupInstance>`):** Hosts the Virtual Network, subnets, Network Security Group, Public IP, Private DNS Zones, all service Private Endpoints, and the single shared User-Assigned Managed Identity.

```
Subscription
  ├── rg-<baseName>-workload-<env>-<instance>
  │     ├── aiHub (Microsoft.MachineLearningServices/workspaces)
  │     ├── aiProject (Microsoft.MachineLearningServices/workspaces)
  │     ├── openAiAccount (Microsoft.CognitiveServices/accounts)
  │     ├── keyVault (Microsoft.KeyVault/vaults)
  │     ├── storageAccount (Microsoft.Storage/storageAccounts)
  │     ├── logAnalytics (Microsoft.OperationalInsights/workspaces)
  │     ├── automationAccount (Microsoft.Automation/automationAccounts)
  │     └── vm (Microsoft.Compute/virtualMachines)
  └── rg-<baseName>-foundation-<env>-<instance>
        ├── vnet (Microsoft.Network/virtualNetworks)
        ├── nsg (Microsoft.Network/networkSecurityGroups)
        ├── publicIp (Microsoft.Network/publicIPAddresses)
        ├── nic (Microsoft.Network/networkInterfaces)
        ├── privateDnsZones (KV, OpenAI, Blob, AzureML)
        ├── privateEndpoints (Storage, KV, OpenAI, AI Hub)
        └── userAssignedIdentity (single shared identity used by Hub, Project, VM, Automation)
```

## Template Configuration

| Resource Name Pattern | Resource Type | Target Scope | Description |
|---|---|---|---|
| `rg-<baseName>-workload-<env>-<instance>` | `Microsoft.Resources/resourceGroups@2024-07-01` | Subscription | Application, data, compute, and AI services resource group |
| `rg-<baseName>-foundation-<env>-<instance>` | `Microsoft.Resources/resourceGroups@2024-07-01` | Subscription | Network isolation, private DNS, private endpoint perimeter, and the shared managed identity |

`<resourceGroupInstance>` is a configurable value (default `001`, set in `variables/core.yaml`) that allows a parallel instance in the same environment. It does not use the 4-character subscription-derived suffix: that suffix is reserved for resources that require global uniqueness across all of Azure (Storage Account, Key Vault, Azure OpenAI account).

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
- [Managed Identity Documentation](managed-identity.md)
- [Documentation Index](index.md)
