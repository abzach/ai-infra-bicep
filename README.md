# Deploy an enterprise-grade Azure AI Foundry environment

This repository provides a streamlined, security-conscious Bicep deployment for Azure AI Foundry and commonly used supporting Azure services. It is designed for learners, developers, and platform engineers who want a practical private-network environment without starting from an empty template.

The project organizes resources into separate core and network resource groups, uses managed identities and private endpoints, and includes a Windows jumpbox with a dual-model terminal chat application. Defaults are cost-conscious, but every deployment still requires review against your organization's security, compliance, quota, and cost requirements.

The code is independently authored and released under the [MIT License](LICENSE) for personal, educational, research, and commercial use.

## Prerequisites

Complete these prerequisites before running `scripts\deploy.ps1`, an Azure DevOps pipeline under `pipelines/`, or a GitHub workflow under `.github/workflows/`.

### Permissions
- Deploying identity (user or service principal) needs **Owner**, or **Contributor** plus **User Access Administrator**, at subscription scope. Resource deployment and RBAC role-assignment permissions are both required.
- Entra **Global Administrator** alone does not grant Azure subscription permissions. Have an administrator with role-assignment write permission grant the required access. Commands printed by the deployment script are single-line commands that can be pasted into PowerShell.

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
git clone https://github.com/abzach/ai-infra-bicep.git
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
- Copy the printed credentials into a password manager, delete `.local\credentials\vm-<environment>.credentials.txt`, and change the VM password after confirming access.
- Use the desktop shortcut `AI Chat` to launch the AI chat terminal app.
- If first-time setup does not start, run `C:\ChatApp\first-run.ps1` from Windows PowerShell in the VM.
- For chat app details, personas, commands, and local development setup, see [app/README.md](app/README.md).

## Azure DevOps pipelines

- Skip this if you cloned the repo earlier:

```powershell
git clone https://github.com/abzach/ai-infra-bicep.git
```

- Create a new Azure DevOps repo and then run:

```powershell
git remote set-url origin https://dev.azure.com/<org>/<project>/_git/<repo>
git push -u origin main
```

- Create a pipeline that points to the appropriate file under `pipelines/`.
- Configure Azure service connection.
- Define `vmAdminPassword` as a protected secret variable or variable-group value.
- Update `variables/dev.yaml` with your environment values before you run the pipeline.

For GitHub Actions, configure OIDC and add repository secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, and `VM_ADMIN_PASSWORD`.

## Overview

| Resource | Public access | Accessible from |
|---|---|---|
| Key Vault | Disabled | VNet private endpoint only (VM); deployment writes secrets through ARM |
| Storage Account | Disabled | VNet private endpoint only |
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
├─ 3. Check for an already-current environment
│     └─ If all expected resources exist and desiredStateHash matches, exit 0
│
├─ 4. Register required Azure resource providers when deployment is needed
│
├─ 5. Detect deployer public IP
│     └─ Restrict the VM RDP NSG rule to that IP
│
├─ 6. Resolve or generate VM admin password
│     └─ Use the supplied password or generate a new one
│
├─ 7. Build deployment parameters JSON
│     └─ Includes: RDP source CIDR, tags, model config, and VM settings
│
├─ 8. Pre-deploy checks
│     ├─ Purge stale ML workspaces (if failed state)
│     ├─ Purge soft-deleted Key Vault / OpenAI (if found)
│     ├─ Remove stale OpenAI diagnostic settings (avoid redeploy Conflict)
│     ├─ Resolve VM Spot priority conflicts
│     └─ Remove stale managed identity role assignments
│
├─ 9. Run Bicep deployment (az deployment sub create)
│     │
│     └─ main.bicep
│           ├─ network.bicep ── VNet, subnets, private DNS zones, NSG, NIC
│           ├─ managedidentity.bicep ── user-assigned identity + RBAC
│           ├─ storageaccount.bicep ── Storage (public access Disabled)
│           ├─ keyvault.bicep ── Key Vault (public access Disabled)
│           ├─ openai.bicep ── Azure OpenAI (public access Disabled)
│           ├─ managedidentityroles.bicep ── RBAC assignments for identity
│           ├─ privateendpoint.bicep ── PE for Storage, KV, OpenAI, AI Hub
│           ├─ aihub.bicep ── AI Hub (public access Disabled)
│           ├─ aiproject.bicep ── AI Project (public access Disabled)
│           ├─ loganalytics.bicep ── Log Analytics workspace
│           └─ vm.bicep ── Windows 11 jumpbox VM
│
├─ 10. Post-deploy configuration
│     ├─ Set Log Analytics daily cap
│     └─ Configure audit diagnostics
│
├─ 11. Sync Key Vault secrets through Azure Resource Manager
│     └─ Write: openai-endpoint, openai-deployment, openai-secondary-deployment,
│               vm-admin-password, keyvault-url, managed-identity-client-id,
│               openai-api-version, config-version
│
├─ 12. Package and bootstrap app files
│      ├─ Generate first-run.ps1 with vault, tenant, and identity metadata
│      └─ Transfer and execute the package through Azure VM Run Command
│           └─ setup.ps1 runs on VM: installs Python, creates venv,
│              copies first-run.ps1, and creates the desktop shortcut
│
└─ 13. Apply the VM password and print the local credential handoff
```

# Configuration

Configuration uses two layers: shared defaults in `variables/core.yaml`, then environment-specific SKU, capacity, identity, and naming choices in `variables/dev.yaml` or `variables/uat.yaml`. Every variable includes its purpose and allowed values inline.

The following operational settings are intentionally configurable because they affect availability, cost, capacity, networking, or retention:

| Area | Configuration |
|---|---|
| Region and network | Azure region, VNet CIDR, services subnet CIDR, VM subnet CIDR, accelerated networking |
| Storage | Redundancy SKU, access tier, artifact container, blob retention, container retention |
| Key Vault | Soft-delete retention |
| Models | Deployment aliases, catalog names, versions, deployment SKUs, and per-environment TPM capacity |
| VM | Size, Marketplace image URN components, OS disk tier, Spot behavior, and auto-shutdown |
| Operations | Diagnostic enablement, Log Analytics retention/daily cap, API versions, and resource tags |
| Identity/pipelines | Per-environment administrator object IDs and Azure DevOps service connection |

Public network restrictions, minimum TLS, OpenAI local-auth disablement, RBAC authorization, Trusted Launch, Secure Boot, vTPM, and Windows client licensing remain enforced in Bicep rather than exposed as environment switches.

The following sections summarize the deployed resources in deployment order.

## 1. Resource groups

- Two resource groups are created per environment: one for core services and one for network resources.
- Both resource groups inherit the shared deployment tag set.
- Tags automatically applied by deployment are: `environment`, `project`, `workload`, `managedBy`, `desiredStateHash`, `createdDate`, and `lastModifiedDate`.
- `desiredStateHash` fingerprints the Bicep, environment YAML, deployment/bootstrap scripts, and app files that define the deployment. A normal rerun exits before making changes when every expected resource exists and this hash matches the local desired state. Use `-ForceRedeploy` to bypass that guard, or `-ForceAppBootstrap` to force VM application transfer.

## 2. Network resources

- Virtual network and subnet CIDRs are configurable; defaults are `10.0.0.0/16`, `10.0.1.0/24` for `services`, and `10.0.2.0/24` for `vm`.
- Both subnets enable service endpoints for `Microsoft.CognitiveServices`, `Microsoft.KeyVault`, and `Microsoft.Storage`.
- Private endpoint network policies are disabled on both subnets so private endpoints can be attached.
- Private DNS zones are created and linked to the VNet for Key Vault, Azure OpenAI, Storage blob, and Azure Machine Learning API resolution.
- Standard static public IP is attached to the VM NIC. Azure allocates the address; the template does not specify an IP address or a custom public IP prefix.
- NIC is associated with an NSG.
- Accelerated networking is configurable and enabled by default for the selected VM SKU.
- NSG rules are generated from deployer allow list: allow RDP from approved CIDRs at priorities starting at `200`, then deny all other RDP at priority `4096`.

### Public IP feature-registration failure

If the public IP operation fails with `SubscriptionNotRegisteredForFeature` naming `Microsoft.Network/AllowBringYourOwnPublicIpAddress`, registration may be required for the affected subscription even though this template uses an Azure-allocated address. ARM template validation can pass while actual public IP creation fails.

Run the following in PowerShell with permission to register subscription features:

```powershell
$subscriptionId = '<affected-subscription-id>'
az feature register --namespace Microsoft.Network --name AllowBringYourOwnPublicIpAddress --subscription $subscriptionId
az feature show --namespace Microsoft.Network --name AllowBringYourOwnPublicIpAddress --subscription $subscriptionId --query properties.state --output tsv
```

Only after the state is `Registered`, propagate the registration and retry deployment:

```powershell
az provider register --namespace Microsoft.Network --subscription $subscriptionId --wait
.\scripts\deploy.ps1 dev
```

Ensure the active Azure CLI subscription matches `$subscriptionId` before running the deployment script. If registration remains pending or public IP creation still fails, contact Azure support with the failed operation details. Do not change the IP to Basic, open the NSG, or supply a custom IP prefix to work around this error.

## 3. Managed identities

- A dedicated user-assigned identity is attached to the VM runtime.
- A separate user-assigned identity is set as the primary identity for the AI Hub.

## 4. Storage account

- `StorageV2` account is deployed.
- Allowed SKUs are `Standard_LRS`, `Standard_GRS`, and `Standard_ZRS`.
- Minimum TLS is set to `TLS1_2`.
- HTTPS-only traffic is enforced.
- Blob public access is disabled at the account level.
- Public network access is disabled; the VM uses the Storage private endpoint.
- Network ACL default action is `Deny`.
- Firewall bypass is set to `AzureServices`.
- `chatapp` blob container is created with `publicAccess` set to `None`.
- Administrator object IDs configured for the environment receive `Storage Blob Data Contributor` on the account.

## 5. Key Vault

- Key Vault is deployed with standard SKU.
- `enableRbacAuthorization` is set to `true`.
- `accessPolicies` is an empty array.
- `enabledForDiskEncryption` is set to `true` to support Azure Disk Encryption.
- Soft delete is enabled with `softDeleteRetentionInDays` set to `7`.
- Public network access is disabled; the VM uses the Key Vault private endpoint.
- Network ACL default action is `Deny`.
- Firewall bypass is set to `AzureServices`.
- Administrator object IDs configured for the environment receive `Key Vault Administrator`. The deploying identity receives `Key Vault Secrets Officer` so deployment can manage secret resources.

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
- `disableLocalAuth` is set to `true`, so API-key authentication is disabled.
- Diagnostic settings are attached and send all logs and all metrics to the shared Log Analytics workspace.
- Two model deployments are created sequentially: the primary deployment first, then the secondary deployment depends on it.
- Shared defaults in `variables/core.yaml` select `gpt-4.1-mini` as primary and `gpt-4.1-nano` as secondary, both version `2025-04-14`. Deployment SKU and capacity are selected per environment in `variables/dev.yaml` and `variables/uat.yaml`.
- The former secondary model, `gpt-4o-mini` version `2024-07-18`, rejected new deployments with `ServiceModelDeprecating` in the target environment. The replacement preserves compatibility with the application's Chat Completions parameters. Model availability and lifecycle status change over time; check the [model lifecycle policy](https://learn.microsoft.com/azure/foundry/openai/concepts/model-retirements) and run deployment preflight before changing versions or regions.

## 8. Role assignments

- The AI Hub identity is granted `Storage Blob Data Contributor`, `Key Vault Secrets User`, and `Cognitive Services OpenAI User`.
- The VM identity is granted `Key Vault Secrets User` and `Cognitive Services OpenAI User`. Application files are delivered through VM Run Command, so the VM does not need Storage data-plane access.

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

- Dev and uat select VM size, image SKU, disk SKU, and Spot behavior in their environment YAML. Shared image publisher, offer, and version values are in `variables/core.yaml`.
- The current environments use `Standard_L2as_v4` in Sweden Central with `microsoftwindowsdesktop:windows-ent-cpc:win11-24h2-ent-cpc-m365:latest`.
- The image is deployed with Trusted Launch, Secure Boot, vTPM, and the `Windows_Client` license type.
- VM always has both a system-assigned identity and a dedicated user-assigned identity.
- VM uses a Standard NIC attached to the dedicated VM subnet and the static public IP.
- Administrator username is parameterized and defaults to `azureadmin`.
- Administrator password is parameterized and stored in Key Vault by the deployment workflow.
- Automatic Windows updates are enabled.
- Patch mode is `AutomaticByOS`.
- VM can run as Spot with `priority` set to `Spot`, `evictionPolicy` set to `Deallocate`, and `maxPrice` configurable.
- An auto-shutdown schedule can be enabled and is on by default.
- RDP is restricted by the NSG to the public IP detected by the deployment script and denied for all other sources.
- Azure Monitor Agent extension is installed.
- IaaS Antimalware extension is installed with real-time protection and a weekly quick scan.
- Azure Disk Encryption extension is installed and configured to encrypt all volumes with Key Vault integration.

## 13. Artifact handling

- Deployment script detects the deployer public IP only to restrict the VM RDP NSG rule.
- Deployment script checks existing resources and the recorded desired-state hash before provider registration or deployment. If the environment is already current, it exits successfully without running Bicep, syncing secrets, bootstrapping the VM, or resetting the password.
- VM administrator passwords are generated as 24-character random values when a password is not supplied. Redeployments rotate that password because a private-only Key Vault does not expose secret values to the deployment host.
- For local runs, successful deployment prints the VM host, username, and password and writes the same values to the ignored `.local\credentials\vm-<environment>.credentials.txt` file. Move the password into a password manager, delete that file, and rotate the VM password after confirming access.
- CI runs never print or write VM credentials; pass `-VmAdminPassword` from the CI secret store.
- Key Vault secrets are synchronized idempotently through Azure Resource Manager, so the deployment does not require Key Vault data-plane network access.
- Secret fingerprints are stored as non-secret content-type metadata to avoid creating redundant secret versions.
- Deployment packages application files locally and transfers them through Azure VM Run Command; it does not require Storage data-plane access from the deployment host.
- On first desktop launch, `first-run.ps1` authenticates the administrator with Azure CLI, reads configuration from Key Vault through the private endpoint, writes `C:\ChatApp\.env`, and starts the app.
- VM runtime receives its dedicated `AZURE_CLIENT_ID` so `DefaultAzureCredential` resolves to the VM identity instead of the system-assigned identity.

## Keeping this documentation current

This README must be updated in the same change as any Bicep, script, app, workflow, or configuration change it describes. See [.github/instructions/documentation-sync.instructions.md](.github/instructions/documentation-sync.instructions.md) for the full doc-to-code mapping, and [.github/instructions/bicep-mcp-server.instructions.md](.github/instructions/bicep-mcp-server.instructions.md) for using the official Bicep MCP server registered in [.mcp.json](.mcp.json).
