# Environment configuration

> **These YAML files are local-only.** `variables/*.yaml` is git-ignored; only the
> `*.yaml.example` templates are committed. Copy the template, fill in your own values, and
> never commit the result. Any new configuration YAML must follow the same rule: commit the
> `.example`, ignore the real file.

## First-time setup

```powershell
Copy-Item variables\core.yaml.example variables\core.yaml
Copy-Item variables\dev.yaml.example  variables\dev.yaml
```

Replace every `<REPLACE_WITH_...>` placeholder (at minimum `admin` and `baseName`).
`scripts/config.ps1` seeds a missing file from its `.example` automatically and then stops with
instructions, and it rejects unreplaced placeholders.

## Environment YAML layout

Keep environment files organized in this order so local files and committed examples stay easy to compare:

1. `Resource prefix` - `environmentSuffix`, `subscriptionId`, and `baseName`.
2. `Deployment flags` - component `deploy*` switches.
3. `Admins` - admin actor object IDs and the RBAC role-name reference assigned by the template.
4. `Users` - user actor object IDs and the RBAC role-name reference assigned by the template.
5. `Configuration` - SKUs, capacities, VM image/disk/DNS, the single-IP RDP shortcut, RDP allowlist CIDRs, Spot choice, and tags.
6. `Automation` - pipeline/service-connection secret-name settings and the service-identity RBAC role-name reference.

## Role-based access control actors

The `admin` and `user` variables configure role assignments for human actors or security groups. The environment YAML comments list the role names exactly where the actors are configured; this table is the full template-assigned reference:

| Principal configured or created by the template | Scope | Role definition names |
|---|---|---|
| `admin` actors | Key Vault | Key Vault Administrator, Key Vault Secrets Officer |
| `admin` actors | Storage Account | Storage Blob Data Owner, Storage Account Contributor |
| `admin` actors | Azure OpenAI | Cognitive Services OpenAI Contributor, Cognitive Services Contributor |
| `admin` actors | Foundry account and project | Foundry Owner, Foundry Project Manager |
| `admin` actors | Jumpbox VM | Virtual Machine Administrator Login |
| `admin` actors | Log Analytics | Log Analytics Contributor, Monitoring Contributor |
| `admin` actors | Core and network resource groups | Contributor, User Access Administrator |
| `user` actors | Key Vault | Key Vault Secrets User, Key Vault Secrets Officer, Key Vault Reader |
| `user` actors | Storage Account | Storage Blob Data Contributor |
| `user` actors | Azure OpenAI | Cognitive Services OpenAI User, Cognitive Services User |
| `user` actors | Foundry project | Foundry User, Foundry Agent Consumer |
| `user` actors | Jumpbox VM | Virtual Machine User Login |
| `user` actors | Log Analytics | Log Analytics Reader, Monitoring Reader |
| `user` actors | Core and network resource groups | Reader |
| Deploying identity | Key Vault | Key Vault Secrets Officer |
| Shared managed identity | Storage Account, Key Vault, Azure OpenAI, Cosmos DB | Storage Blob Data Contributor, Key Vault Secrets User, Cognitive Services OpenAI User, Cosmos DB Built-in Data Contributor |
| Shared managed identity | Jumpbox VM; jumpbox NSG | Virtual Machine Contributor; Network Contributor |

Both support arrays of objects (`- objectId: '...', principalType: 'User'|'Group'|'ServicePrincipal'`) or simple object ID strings. Leaving an array empty (`[]`) skips role assignments cleanly.

Configuration is merged in this order:

1. `core.yaml` shared defaults
2. `dev.yaml` or `uat.yaml` environment overrides
3. Subscription-derived name suffix calculated from the environment YAML `subscriptionId`

If a failed Foundry creation leaves the `agent` subnet linked to Agent Service, set `agentRecoverySubnetAddressPrefix` in the environment YAML to an unused, non-overlapping `/24` within `vnetAddressSpace`. This adds an `agent-recovery` subnet without removing the original one. Leave the setting empty for normal deployments; do not change it back while the Foundry account uses the recovery subnet.

## Component deployment flags

Each environment file carries `deploy*` flags. `true` deploys the component and keeps it
current; `false` makes the next `scripts/deploy.ps1` run remove it if a previous run created it.

| Flag | Deploys | Removed when `false` |
|---|---|---|
| `deployStorage` | Storage account, blob container, blob private endpoint | Private endpoint, then the storage account |
| `deployLogAnalytics` | Log Analytics workspace and resource diagnostics | Diagnostic settings, then the workspace |
| `deployAiFoundry` | Foundry account/project, Agent Service, Azure AI Search, Agent subnet, private endpoints, and DNS | Capability hosts and project before account; private endpoints/Search and Agent subnet afterward |
| `deployVm` | Jumpbox VM, NIC, public IP, NSG, OS disk, auto-shutdown schedule | Schedule, VM, **OS disk**, NIC, public IP, NSG |
| `deployAutomation` | Automation Account, repository runbooks | Automation Account (the shared identity is never removed) |
| `deployPostgres` | PostgreSQL Flexible Server, delegated subnet, private DNS zone | Server, delegated subnet, private DNS zone |
| `deployStaticWebApp` | Azure Static Web Apps on the Free plan | Static Web App |
| `deployCosmosDb` | Cosmos DB account, SQL database/container, private endpoint, private DNS zone | Account, private endpoint, private DNS zone |
| `deployApiManagement` | API Management service on the Consumption tier | API Management service |
| `deployAppService` | Linux App Service and App Service plan on the F1 Free tier | App Service, then App Service plan |

Components without a flag are never removed because they hold deployment state or everything
else depends on them: resource groups, the base virtual network and subnets, shared private DNS
zones and links, Key Vault and its private endpoint, Azure OpenAI and its private endpoint, and
the shared managed identity.

Dependency rules enforced by `scripts/config.ps1`:

- `deployAiFoundry` requires both `deployStorage` and `deployCosmosDb`; Azure AI Search is deployed with Foundry.
- `privateAiWorkspacesOnly` must remain `true`; Foundry public network access is disabled, so its private endpoint is required.
- `enableAuditDiagnostics` requires `deployLogAnalytics`
- `deployAutomation` requires `deployVm`
- `vmStartScheduleEnabled` requires `deployAutomation`
- `rdpDeployerCleanupScheduleEnabled` requires `deployAutomation`
- `vmAutoShutdownEnabled` requires `deployVm`

## Where values belong

All location, Storage tier, model deployment arrays, model/API versions, VM shutdown settings, tags, SKU/capacity, environment identity, service-connection selections, GitHub OIDC secret-name selections, and optional public IP DNS labels belong in the environment YAML. Shared networking, retention, image publisher/offer/version, Automation runtime/schedule, guest time zone, and operational defaults belong in `core.yaml`. Every variable must retain an inline purpose and allowed-values comment.

`subscriptionId` is the Azure subscription GUID that owns the environment. Local scripts load it before deriving resource names, set the Azure CLI context to that subscription, and then calculate the four-character name suffix from it. This prevents `*-deploy`, `*-connect`, `*-clean`, and deployed-environment tests from accidentally targeting whichever subscription was active before the command started.

`vmPublicIpDnsNameLabel` configures the optional DNS label on the jumpbox VM public IP. Leave it empty (`''`) to deploy only the static public IP address, or set a region-unique label such as `az-swe-aifp` to produce an Azure DNS name like `az-swe-aifp.swedencentral.cloudapp.azure.com` when `location` is `swedencentral`.

`modelDeployments` is an ordered array of objects with `deploymentName`, `modelName`, `modelVersion`, `skuName`, and positive `capacityK`. At least two entries are required because the chat app consumes the first two as primary and secondary models; any number of additional deployments is supported.

`deployPostgres` deploys an Azure Database for PostgreSQL Flexible Server sized to the Azure free-tier allowance: `postgresSkuName` (`Standard_B1ms`, Burstable tier) in the environment YAML, and `postgresSubnetAddressPrefix`, `postgresAdminUsername`, `postgresVersion`, `postgresStorageSizeGB`, and `postgresBackupRetentionDays` as shared defaults in `core.yaml`. The administrator password is generated and stored in Key Vault by `deploy.ps1`; see [PostgreSQL](../docs/postgresql.md).

`deployStaticWebApp` deploys Azure Static Web Apps on the Free hosting plan. `staticWebAppSkuName` is restricted to `Free`; see [Azure Static Web Apps](../docs/static-web-apps.md).

`deployCosmosDb` deploys Azure Cosmos DB for NoSQL with free tier enabled, public network access and local key authentication disabled, a private endpoint, and an initial SQL database/container. `cosmosDbThroughput` defaults to 400 RU/s and is validated between 400 and 1000 RU/s to stay within the free-tier throughput allowance; see [Azure Cosmos DB](../docs/cosmos-db.md).

`deployApiManagement` deploys Azure API Management on the Consumption tier. `apiManagementSkuName` is restricted to `Consumption`; keep usage at or below 1 million API calls per month when targeting the free allowance. `apiManagementPublisherEmail` and `apiManagementPublisherName` provide the required APIM publisher metadata; see [Azure API Management](../docs/api-management.md).

`rdpAllowedPublicIpAddress` and `rdpAllowedIpCidrs` populate `allow-rdp-user`. The detected deploying or connecting machine populates `allow-rdp-deployer`, which the weekly Automation runbook deletes without changing the user rule. Use `main.ps1 dev-connect -WhatIf` or `main.ps1 uat-connect -WhatIf` before applying a live update.

GitHub Actions deployment and cleanup workflows read these environment YAML keys before `azure/login`:

| Variable | Default value | Purpose |
|---|---|---|
| `githubAzureClientIdSecretName` | `AZURE_CLIENT_ID` | Name of the GitHub secret containing the OIDC application/client ID |
| `githubAzureTenantIdSecretName` | `AZURE_TENANT_ID` | Name of the GitHub secret containing the Microsoft Entra tenant ID |
| `githubAzureSubscriptionIdSecretName` | `AZURE_SUBSCRIPTION_ID` | Name of the GitHub secret containing the Azure subscription ID |

Change the values, for example to `AZURE_CLIENT_ID_01`, `AZURE_TENANT_ID_01`, and `AZURE_SUBSCRIPTION_ID_01`, when an environment should use differently named GitHub secrets.

`scripts/config.ps1` is the authoritative parser and validator. Update it, its `.example` templates, Bicep parameters, tests, and documentation whenever a variable is added or renamed.

For tabular specifications of resources configured by these variables, see the [Architecture Documentation](../docs/README.md).

Update this README whenever a variable is added, renamed, or moved between `core.yaml` and an environment file; see [../.github/instructions/documentation-sync.instructions.md](../.github/instructions/documentation-sync.instructions.md).
