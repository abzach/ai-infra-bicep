# Bicep modules

| Module | Responsibility |
|---|---|
| `network.bicep` | VNet, subnets, NSG, NIC, public IP, and private DNS |
| `managedidentity.bicep` | User-assigned managed identity |
| `managedidentityroles.bicep` | Least-privilege workload data-plane roles |
| `storageaccount.bicep` | Private Storage account and blob container |
| `keyvault.bicep` | Private RBAC-enabled Key Vault |
| `openai.bicep` | Private Azure OpenAI account and two model deployments |
| `privateendpoint.bicep` | Reusable private endpoint and DNS zone group |
| `aihub.bicep` | Private AI Hub workspace and connection |
| `aiproject.bicep` | Private AI Project workspace |
| `loganalytics.bicep` | Log Analytics workspace |
| `vm.bicep` | Windows jumpbox, extensions, and auto-shutdown |

Modules are orchestrated by `../templates/main.bicep`. Keep module interfaces explicit and preserve the security invariants in the root `AGENTS.md`.
