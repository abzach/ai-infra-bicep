# Deploy enterprise grade AI Foundry

This repository provides a streamlined template to deploy AI resources on Azure. It is designed for learners to explore AI Foundry and related services without worrying about security compliance. With this template, all key resources are organized into resource groups, carefully optimized to keep costs low providing a simple yet robust structure for deploying and managing  AI projects.

Beyond just deployment, this template is a learning tool. It's designed to help you understand infrastructure-as-code using Bicep enabling collaboration between infrastructure and development teams. It provides a solid foundation for expanding your cloud skills horizontally as you work toward new AI innovations.

With an intuitive, terminal-based chat experience that brings two different AI models to life, this project was created as an invitation to experiment, learn, and innovate within the Azure AI landscape

## Prerequisites

- You **need** to complete below steps before you begin with the **Getting Started section**
- This is required before you run Powershell script `scripts\deploy.ps1` or Azure DevOps pipeline `pipelines\deploy-dev.yml` or GitHub workflows `.github\workflows\deploy-dev.yml`

### Permissions
- Deploying identity (user or service principal) must have **Owner** role at subscription scope level. This is required because the bicep template creates Azure RBAC role assignments for application functionality

### Packages
- [Git](https://git-scm.com/download/win)
- [Azure CLI v2.60+](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)

```powershell
git --version
az --version
$PSVersionTable.PSVersion
```

## Getting started

- Clone repository:

```powershell
git clone https://github.com/abzach/foundry-bicep.git
```

- Sign in to Azure:

```powershell
az login
```

- Update settings in `variables/dev.yaml` or `variables/uat.yaml` before deployment:
- `baseName` — short prefix for resource naming (max 5-8 chars, e.g. `mstech`)
- `adminObjectIds` — your user's Entra ID object ID(s), comma-separated

- Run deployment:

```powershell
.\scripts\deploy.ps1 dev
```

- Connect to the VM by using RDP.
- Use the desktop shortcut `AI Chat` to launch the AI chat terminal app
- If it doesn't, you can try rerunning first-time setup, start `C:\ChatApp\first-run.ps1` from Windows PowerShell.
- For chat app details, personas, commands, and local development setup, see [app/README.md](app/README.md).

## Azure DevOps pipelines

- Skip this if you cloned the repo earlier:

```powershell
git clone https://github.com/abzach/foundry-bicep.git
```

- Create a new Azure DevOps repo and then run:

```powershell
git remote set-url origin https://dev.azure.com/<org>/<project>/_git/<repo>
git push -u origin main
```

- Create a pipeline that points to the appropriate file under `pipelines/`.
- Configure Azure service connection.
- Update `variables/dev.yaml` with your environment values before you run the pipeline.

## Overview

| Resource | Public access | Accessible from |
|---|---|---|
| Key Vault | Enabled (selected networks) | Deployer IP + VNet services subnet |
| Storage Account | Enabled (selected networks) | Deployer IP + VNet services subnet |
| Azure OpenAI | Disabled | VNet private endpoint only (VM) |
| AI Hub / AI Project | Disabled | VNet private endpoint only (VM) |
| Jumpbox VM | Public IP with NSG | RDP from deployer IP only |

- Access Azure OpenAI, AI Hub, and AI Project from inside the VM through private endpoints.

## Workflow

- `deploy.ps1` runs the following sequence:

```
deploy.ps1 -EnvironmentSuffix dev
│
├─ 1. Validate Azure CLI session (az account show)
│
├─ 2. Load config from variables/dev.yaml
│     └─ config.ps1 → Read-EnterpriseEnvironmentConfig()
│
├─ 3. Detect deployer public IP
│     ├─ Add IP to Key Vault firewall (az keyvault network-rule add)
│     └─ Add IP to Storage Account firewall (az storage account network-rule add)
│
├─ 4. Resolve or generate VM admin password
│     └─ Read from Key Vault or create new
│
├─ 5. Build deployment parameters JSON
│     └─ Includes: IP allow lists, tags, model config, VM settings
│
├─ 6. Pre-deploy checks
│     ├─ Purge stale ML workspaces (if failed state)
│     ├─ Purge soft-deleted Key Vault / OpenAI (if found)
│     ├─ Remove stale OpenAI diagnostic settings (avoid redeploy Conflict)
│     ├─ Resolve VM Spot priority conflicts
│     └─ Remove stale managed identity role assignments
│
├─ 7. Run Bicep deployment (az deployment sub create)
│     │
│     └─ main.bicep
│           ├─ network.bicep ── VNet, subnets, private DNS zones, NSG, NIC
│           ├─ managedidentity.bicep ── user-assigned identity + RBAC
│           ├─ storageaccount.bicep ── Storage (Deny default + IP/subnet allow)
│           ├─ keyvault.bicep ── Key Vault (Deny default + IP/subnet allow)
│           ├─ openai.bicep ── Azure OpenAI (public access Disabled)
│           ├─ managedidentityroles.bicep ── RBAC assignments for identity
│           ├─ privateendpoint.bicep ── PE for Storage, KV, OpenAI, AI Hub
│           ├─ aihub.bicep ── AI Hub (public access Disabled)
│           ├─ aiproject.bicep ── AI Project (public access Disabled)
│           ├─ loganalytics.bicep ── Log Analytics workspace
│           └─ vm.bicep ── Windows 11 jumpbox VM
│
├─ 8. Post-deploy configuration
│     ├─ Set Log Analytics daily cap
│     └─ Configure audit diagnostics
│
├─ 9. Sync Key Vault secrets
│     ├─ Wait for Key Vault DNS resolution
│     └─ Write: openai-endpoint, openai-deployment, openai-secondary-deployment,
│               vm-admin-password, keyvault-url, managed-identity-client-id,
│               openai-api-version, config-version, storage-account-key, storage-account-key2
│
├─ 10. Package & upload app files
│      ├─ Generate first-run.ps1 with baked-in secret values
│      ├─ Retrieve storage account keys → sync to Key Vault
│      ├─ Upload chat.py, test.py, requirements.txt, first-run.ps1, setup.ps1 to blob
│      └─ Apply Custom Script Extension to VM
│           └─ setup.ps1 runs on VM: installs Python, creates venv,
│              runs first-run.ps1 to write .env, creates desktop shortcut
│
└─ 11. Reset VM admin password from Key Vault secret
```

# Configuration

- The following sections summarize the deployed resources in deployment order.

## 1. Resource groups

- Two resource groups are created per environment: one for core services and one for network resources.
- Both resource groups inherit the shared deployment tag set.
- Tags are automatically applied by deployment are: `environment`, `project`, `workload`, `managedBy`, `createdDate`, and `lastModifiedDate`.

## 2. Network resources

- Virtual network is deployed with address space `10.0.0.0/16`.
- Two subnets are created in order: `services` on `10.0.1.0/24` and `vm` on `10.0.2.0/24`.
- Both subnets enable service endpoints for `Microsoft.CognitiveServices`, `Microsoft.KeyVault`, and `Microsoft.Storage`.
- Private endpoint network policies are disabled on both subnets so private endpoints can be attached.
- Private DNS zones are created and linked to the VNet for Key Vault, Azure OpenAI, Storage blob, and Azure Machine Learning API resolution.
- Standard static public IP is attached to the VM NIC.
- NIC is associated with an NSG.
- NSG rules are generated from deployer allow list: allow RDP from approved CIDRs at priorities starting at `200`, then deny all other RDP at priority `4096`.

## 3. Managed identities

- A dedicated user-assigned identity is attached to the VM runtime.
- A separate user-assigned identity is set as the primary identity for the AI Hub.

## 4. Storage account

- `StorageV2` account is deployed.
- Allowed SKUs are `Standard_LRS`, `Standard_GRS`, and `Standard_ZRS`.
- Minimum TLS is set to `TLS1_2`.
- HTTPS-only traffic is enforced.
- Blob public access is disabled at the account level.
- Public network access remains enabled, but the firewall default action is `Deny`.
- Network rules allow only the configured IP CIDRs and the services subnet.
- Firewall bypass is set to `AzureServices`.
- `chatapp` blob container is created with `publicAccess` set to `None`.
- Deployer receives `Storage Blob Data Contributor` on the account.

## 5. Key Vault

- Key Vault is deployed with standard SKU.
- `enableRbacAuthorization` is set to `true`.
- `accessPolicies` is an empty array.
- `enabledForDiskEncryption` is set to `true` to support Azure Disk Encryption.
- Soft delete is enabled with `softDeleteRetentionInDays` set to `7`.
- Public network access remains enabled, but the firewall default action is `Deny`.
- Network rules allow only the configured IP CIDRs and the services subnet.
- Firewall bypass is set to `AzureServices`.
- Deployer receives the `Key Vault Administrator` role.

## 6. Log Analytics workspace

- Log Analytics workspace deployed with SKU `PerGB2018`.
- Retention is configurable and defaults to `30` days in the environment configuration.
- `enableLogAccessUsingOnlyResourcePermissions` is set to `true`.
- Deployment script sets a daily ingestion cap, which defaults to `0.5` GB in the environment configuration.

## 7. Azure OpenAI and models

- Azure OpenAI account deployed with SKU `S0` and kind `OpenAI`.
- Custom subdomain is configured on the account.
- `publicNetworkAccess` is set to `Disabled`.
- `networkAcls.defaultAction` is set to `Deny`.
- `disableLocalAuth` is set to `false`.
- Diagnostic settings are attached and send all logs and all metrics to the shared Log Analytics workspace.
- Two model deployments are created sequentially: the primary deployment first, then the secondary deployment depends on it.
- Default environment values deploy `gpt-4.1-mini` as primary and `gpt-4o-mini` as secondary.

## 8. Role assignments

- The AI Hub identity is granted `Storage Blob Data Contributor`, `Key Vault Secrets User`, and `Cognitive Services OpenAI User`.
- The VM identity is granted `Storage Blob Data Reader`, `Key Vault Secrets User`, and `Cognitive Services OpenAI User`.

## 9. Private endpoints

- Private endpoint is created for Storage blob access.
- Private endpoint is created for Key Vault.
- Private endpoint is created for the Azure OpenAI account.
- Private endpoint is created for the AI Hub workspace when private AI workspaces are enabled.
- Each private endpoint is attached to the services subnet.
- Each private endpoint is associated with the matching private DNS zone group when a DNS zone ID is supplied.

## 10. AI Hub

- Azure Machine Learning workspace is deployed with kind `Hub` and SKU `Basic`.
- Workspace uses the user-assigned managed identity.
- `primaryUserAssignedIdentity` is set to that identity.
- Workspace is wired to the deployed storage account and Key Vault.
- Public network access is disabled.
- `allowPublicAccessWhenBehindVnet` is set to `false`.
- Azure OpenAI connection is created with `authType` set to `AAD` and `isSharedToAll` set to `true`.
- Diagnostic settings are attached and send all logs and all metrics to the shared Log Analytics workspace.

## 11. AI Project

- Machine Learning workspace deployed with kind `Project` and SKU `Basic`.
- Project uses a system-assigned identity.
- Project is linked to the Hub by `hubResourceId`.
- Public network access is disabled.
- `allowPublicAccessWhenBehindVnet` is set to `false`.

## 12. Virtual machine

- Windows 11 Enterprise
- VM always has both a system-assigned identity and the shared user-assigned identity.
- VM uses a Standard NIC attached to the dedicated VM subnet and the static public IP.
- Administratorr username is parameterized and defaults to `azureadmin`.
- Administrator password is parameterized and stored in Key Vault by the deployment workflow.
- Automatic Windows updates are enabled.
- Patch mode is `AutomaticByOS`.
- VM can run as Spot with `priority` set to `Spot`, `evictionPolicy` set to `Deallocate`, and `maxPrice` configurable.
- An auto-shutdown schedule can be enabled and is on by default.
- Just-in-time (JIT) access is enabled, allowing secure connections directly from the Azure portal without exposing the VM to constant network access.
- Azure Monitor Agent extension is installed.
- IaaS Antimalware extension is installed with real-time protection and a weekly quick scan.
- Azure Disk Encryption extension is installed and configured to encrypt all volumes with Key Vault integration.

## 13. Artifact handling

- Deployment script detects the deployer public IP and adds it to the Key Vault and Storage firewalls before secret and artifact operations.
- VM administrator passwords are generated as 24-character random values when a password is not supplied.
- Existing VM administrator passwords are reused from Key Vault on redeployment when present.
- Key Vault secrets are synchronized idempotently so unchanged values do not create new secret versions.
- Secrets are written with direct value submission instead of temporary plaintext files.
- Storage account keys are retrieved contextually during script execution and securely logged within the Key Vault.
- Deployment uploads application artifacts alongside a dynamically populated `first-run.ps1` script to the private blob container and applies the VM Custom Script Extension.
- `first-run.ps1` runs securely within the VM deployment context, generating `.env` contents dynamically.
- VM runtime receives its dedicated `AZURE_CLIENT_ID` so `DefaultAzureCredential` resolves to the VM identity instead of the system-assigned identity.
