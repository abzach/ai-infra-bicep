# Bicep modules

| Module | Responsibility | Dedicated Documentation |
|---|---|---|
| `network.bicep` | VNet, private-endpoint/VM/PostgreSQL/Agent subnets (plus optional Agent recovery subnet), named RDP rules, NIC, public IP, and private DNS | [Virtual Network Doc](../../docs/virtual-network.md) |
| `managedidentity.bicep` | Shared user-assigned identity used by the VM and Automation workloads | [Managed Identity Doc](../../docs/managed-identity.md) |
| `managedidentityroles.bicep` | Least-privilege workload data-plane roles for the shared identity | [RBAC Doc](../../docs/role-based-access-control.md) |
| `actorroles.bicep` | Admin and user RBAC assignments across Workload Resource Group services | [RBAC Doc](../../docs/role-based-access-control.md) |
| `networkroles.bicep` | Admin and user RBAC assignments on the Foundation Resource Group, the Foundry account/project, and the jumpbox VM | [RBAC Doc](../../docs/role-based-access-control.md) |
| `storageaccount.bicep` | Private Storage account and blob container | [Storage Account Doc](../../docs/storage-account.md) |
| `keyvault.bicep` | Private RBAC-enabled Key Vault | [Key Vault Doc](../../docs/key-vault.md) |
| `openai.bicep` | Private Azure OpenAI account and an arbitrary configured array of model deployments | [Azure OpenAI Doc](../../docs/azure-openai.md) |
| `privateendpoint.bicep` | Reusable private endpoint with single- or multi-zone DNS registration | [Private Endpoints Doc](../../docs/private-endpoints.md) |
| `foundry.bicep` | Private `AIServices` account, child project, model deployments, AAD connections, and diagnostics | [Foundry Account Doc](../../docs/foundry-account.md) |
| `foundryroles.bicep` | Agent project identity roles on Storage, Cosmos DB, and AI Search (the Foundry account role is assigned in `foundry.bicep`) | [RBAC Doc](../../docs/role-based-access-control.md) |
| `foundrycapabilityhost.bicep` | Agent capability host bound to tenant-owned backing-resource connections | [Foundry Project Doc](../../docs/ai-project.md) |
| `aisearch.bicep` | Private AAD-only Azure AI Search service for Agent vector stores | [Azure AI Search Doc](../../docs/ai-search.md) |
| `aihub.bicep` | Legacy Hub module retained for migration history; no longer orchestrated | [Foundry Account Doc](../../docs/foundry-account.md) |
| `aiproject.bicep` | Legacy AML Project module retained for migration history; no longer orchestrated | [Foundry Project Doc](../../docs/ai-project.md) |
| `loganalytics.bicep` | Log Analytics workspace | [Log Analytics Doc](../../docs/log-analytics.md) |
| `vm.bicep` | Windows jumpbox, attach-aware extensions, and auto-shutdown | [Virtual Machine Doc](../../docs/virtual-machine.md) |
| `automation.bicep` | Automation Account, PowerShell runtime/runbooks, daily VM start and weekly RDP cleanup schedules, and VM-scoped RBAC | [Automation Account Doc](../../docs/automation-account.md) |
| `postgresflexibleserver.bicep` | PostgreSQL Flexible Server sized to the Azure free-tier allowance (Burstable B1ms, 32 GiB, HA disabled), VNet-integrated via a delegated subnet | [PostgreSQL Doc](../../docs/postgresql.md) |
| `staticwebapp.bicep` | Azure Static Web Apps resource on the Free hosting plan | [Static Web Apps Doc](../../docs/static-web-apps.md) |
| `cosmosdb.bicep` | Azure Cosmos DB for NoSQL free-tier account with private endpoint support, disabled local auth, SQL database/container, and managed-identity SQL RBAC | [Cosmos DB Doc](../../docs/cosmos-db.md) |
| `apimanagement.bicep` | Azure API Management service on the Consumption tier | [API Management Doc](../../docs/api-management.md) |
| `appservice.bicep` | Public Linux App Service and plan on the F1 Free tier | [App Service Doc](../../docs/app-service.md) |

Modules are orchestrated by `../templates/main.bicep`. Foundry Agent capability-host creation waits for project RBAC and private endpoints. Actor RBAC assignments depend on the optional target modules. Keep module interfaces explicit and preserve the security invariants in the root `AGENTS.md`.

Update this table whenever a module is added, removed, or renamed; see [../../.github/instructions/documentation-sync.instructions.md](../../.github/instructions/documentation-sync.instructions.md). Use the Bicep MCP server (see [../../.github/instructions/bicep-mcp-server.instructions.md](../../.github/instructions/bicep-mcp-server.instructions.md)) for resource type/schema lookups when adding or changing a module.
