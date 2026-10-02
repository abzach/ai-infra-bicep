# Resource Groups

This document describes the dual Resource Group architecture deployed at subscription scope by `bicep/templates/main.bicep`.

## Architecture & Responsibilities

The deployment splits infrastructure into two distinct resource groups: one for workload-facing application/AI services and their globally-unique-named data, and one for networking, security perimeter, and the shared identity:

1. **Workload Resource Group (`rg-<baseName>-workload-<environmentSuffix>-<resourceGroupInstance>`):** Hosts the data and model services: Azure OpenAI, Azure AI Search, Key Vault, Storage Account, Cosmos DB, PostgreSQL, Log Analytics, and the Static Web App.
2. **Foundation Resource Group (`rg-<baseName>-foundation-<environmentSuffix>-<resourceGroupInstance>`):** Hosts the Virtual Network, subnets, Network Security Group, Public IP, Private DNS Zones, all service Private Endpoints, the single shared User-Assigned Managed Identity, the Microsoft Foundry account/project, the Jumpbox VM and its OS disk, the Automation Account and runbooks, API Management, and the App Service plan and app.

```
Subscription
  ├── rg-<baseName>-workload-<env>-<instance>
  │     ├── aiSearch (Microsoft.Search/searchServices)
  │     ├── openAiAccount (Microsoft.CognitiveServices/accounts)
  │     ├── keyVault (Microsoft.KeyVault/vaults)
  │     ├── storageAccount (Microsoft.Storage/storageAccounts)
  │     ├── cosmosDb (Microsoft.DocumentDB/databaseAccounts)
  │     ├── postgres (Microsoft.DBforPostgreSQL/flexibleServers)
  │     ├── staticWebApp (Microsoft.Web/staticSites)
  │     └── logAnalytics (Microsoft.OperationalInsights/workspaces)
  └── rg-<baseName>-foundation-<env>-<instance>
        ├── foundryAccount (Microsoft.CognitiveServices/accounts, kind AIServices)
        ├── foundryProject (Microsoft.CognitiveServices/accounts/projects)
        ├── vm + OS disk (Microsoft.Compute/virtualMachines, Microsoft.Compute/disks)
        ├── automationAccount + runbooks (Microsoft.Automation/automationAccounts)
        ├── apiManagement (Microsoft.ApiManagement/service)
        ├── appServicePlan + app (Microsoft.Web/serverfarms, Microsoft.Web/sites)
        ├── vnet (Microsoft.Network/virtualNetworks)
        ├── nsg (Microsoft.Network/networkSecurityGroups)
        ├── publicIp (Microsoft.Network/publicIPAddresses)
        ├── nic (Microsoft.Network/networkInterfaces)
        ├── privateDnsZones (KV, OpenAI, Blob, AzureML)
        ├── privateEndpoints (Storage, KV, OpenAI, Foundry, Search, Cosmos DB)
        ├── agent subnet (Microsoft.App/environments delegation)
        └── userAssignedIdentity (single shared identity used by Hub, Project, VM, Automation)
```

### Migrating an existing environment

Earlier revisions deployed Foundry, the VM, Automation, API Management, and App Service to the workload group. `scripts/deploy.ps1` migrates them before the Bicep deployment, and `-WhatIf` previews the migration:

- Automation Account, API Management, and the App Service plan with its apps move with `az resource move`; old Automation job-schedule links are removed and recreated after runbook publication.
- Spot VMs cannot be moved, so the VM is deleted with its OS disk detached, the disk moves, and Bicep recreates the VM attached to it. This requires `vmExistingOsDiskId` to point at the disk in the foundation group, and the VM gets a new admin password because it is recreated.
- Moving a Foundry account leaves project identities and the Agent Service capability host unusable. The script deletes its projects, deletes and purges the old account, and Bicep recreates the account, project, and private endpoint in the foundation group. Preserve any project data before migrating.

## Template Configuration

| Resource Name Pattern | Resource Type | Target Scope | Description |
|---|---|---|---|
| `rg-<baseName>-workload-<env>-<instance>` | `Microsoft.Resources/resourceGroups@2024-07-01` | Subscription | Data, model, and static-hosting services resource group |
| `rg-<baseName>-foundation-<env>-<instance>` | `Microsoft.Resources/resourceGroups@2024-07-01` | Subscription | Network isolation, private endpoint perimeter, shared managed identity, Foundry, compute, automation, and API/app hosting |

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
