# Bicep modules

| Module | Responsibility | Dedicated Documentation |
|---|---|---|
| `network.bicep` | VNet, subnets, named RDP rules, Automation NSG role, NIC, public IP, and private DNS | [Virtual Network Doc](../../docs/virtual-network.md) |
| `managedidentity.bicep` | User-assigned managed identity | [Managed Identity Doc](../../docs/managed-identity.md) |
| `managedidentityroles.bicep` | Least-privilege workload data-plane roles | [RBAC Doc](../../docs/role-based-access-control.md) |
| `actorroles.bicep` | Admin and user RBAC assignments across Core Resource Group services | [RBAC Doc](../../docs/role-based-access-control.md) |
| `networkroles.bicep` | Admin and user RBAC assignments across Network Resource Group services | [RBAC Doc](../../docs/role-based-access-control.md) |
| `storageaccount.bicep` | Private Storage account and blob container | [Storage Account Doc](../../docs/storage-account.md) |
| `keyvault.bicep` | Private RBAC-enabled Key Vault | [Key Vault Doc](../../docs/key-vault.md) |
| `openai.bicep` | Private Azure OpenAI account and an arbitrary configured array of model deployments | [Azure OpenAI Doc](../../docs/azure-openai.md) |
| `privateendpoint.bicep` | Reusable private endpoint and DNS zone group | [Private Endpoints Doc](../../docs/private-endpoints.md) |
| `aihub.bicep` | Private AI Hub workspace and connection | [AI Hub Doc](../../docs/ai-hub.md) |
| `aiproject.bicep` | Private AI Project workspace | [AI Project Doc](../../docs/ai-project.md) |
| `loganalytics.bicep` | Log Analytics workspace | [Log Analytics Doc](../../docs/log-analytics.md) |
| `vm.bicep` | Windows jumpbox, extensions, and auto-shutdown | [Virtual Machine Doc](../../docs/virtual-machine.md) |
| `automation.bicep` | Automation Account, PowerShell runtime/runbooks, daily VM start and weekly RDP cleanup schedules, and VM-scoped RBAC | [Automation Account Doc](../../docs/automation-account.md) |

Modules are orchestrated by `../templates/main.bicep`. Actor RBAC assignments depend on the optional resource modules they target, so recreated Storage, AI Hub, AI Project, VM, or Log Analytics resources exist before roles are applied. Keep module interfaces explicit and preserve the security invariants in the root `AGENTS.md`.

Update this table whenever a module is added, removed, or renamed; see [../../.github/instructions/documentation-sync.instructions.md](../../.github/instructions/documentation-sync.instructions.md). Use the Bicep MCP server (see [../../.github/instructions/bicep-mcp-server.instructions.md](../../.github/instructions/bicep-mcp-server.instructions.md)) for resource type/schema lookups when adding or changing a module.
