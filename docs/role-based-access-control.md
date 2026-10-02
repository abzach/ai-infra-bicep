# Role-Based Access Control (RBAC)

This document details all Azure RBAC role assignments provisioned by `bicep/modules/managedidentityroles.bicep`, `bicep/modules/automation.bicep`, `keyvault.bicep`, and `storageaccount.bicep`.

## RBAC Matrix & Principles

The environment follows strict least-privilege principles. No service or identity is granted broad subscription-wide permissions. All role assignments are scoped directly to the target Azure resource.

### Deploying-identity preflight

Creating these assignments requires role-assignment write permission (`Owner` or `User Access Administrator`) at subscription scope. `scripts/deploy.ps1` verifies this before deploying and self-remediates when possible:

1. Detect an effective `Owner` or `User Access Administrator` assignment, including inherited ones.
2. Short-circuit when one is already present.
3. Attempt to grant `User Access Administrator` at subscription scope to the deploying identity.
4. For an interactive user only, attempt Entra `elevateAccess` and retry the grant. Skipped in CI and when `-SkipRoleElevation` is passed.
5. Re-verify with backoff to absorb RBAC propagation delay.
6. Fail with the exact administrator request only after every remediation attempt fails.

```
Principal                          Scope               Role Definition Name
─────────────────────────────────────────────────────────────────────────────────────────────
Shared Managed Identity             Storage Account     Storage Blob Data Contributor
Shared Managed Identity             Key Vault           Key Vault Secrets User
Shared Managed Identity             Azure OpenAI        Cognitive Services OpenAI User
Shared Managed Identity             Cosmos DB           Cosmos DB Built-in Data Contributor (SQL RBAC)
Shared Managed Identity             Jumpbox VM          Virtual Machine Contributor
─────────────────────────────────────────────────────────────────────────────────────────────
Deploying Identity (SP/User)       Key Vault           Key Vault Secrets Officer
─────────────────────────────────────────────────────────────────────────────────────────────
Admin Actors (Full Access)         Key Vault           Key Vault Administrator, Key Vault Secrets Officer
Admin Actors (Full Access)         Storage Account     Storage Blob Data Owner, Storage Account Contributor
Admin Actors (Full Access)         Azure OpenAI        Cognitive Services OpenAI Contributor, Cognitive Services Contributor
Admin Actors (Full Access)         Foundry             Foundry Owner, Foundry Project Manager
Admin Actors (Full Access)         Jumpbox VM          Virtual Machine Administrator Login
Admin Actors (Full Access)         Log Analytics       Log Analytics Contributor, Monitoring Contributor
Admin Actors (Full Access)         Resource Groups     Contributor, User Access Administrator
─────────────────────────────────────────────────────────────────────────────────────────────
User Actors (Operational Access)   Key Vault           Key Vault Secrets User, Key Vault Secrets Officer, Key Vault Reader
User Actors (Operational Access)   Storage Account     Storage Blob Data Contributor
User Actors (Operational Access)   Azure OpenAI        Cognitive Services OpenAI User, Cognitive Services User
User Actors (Operational Access)   Foundry Project     Foundry User, Foundry Agent Consumer
User Actors (Operational Access)   Jumpbox VM          Virtual Machine User Login
User Actors (Operational Access)   Log Analytics       Log Analytics Reader, Monitoring Reader
User Actors (Operational Access)   Resource Groups     Reader
```

> **Single-identity trade-off:** the roles above the "Deploying Identity" line that used to be split across three identities (Hub, VM, Automation) are now all granted to one shared identity. See [Managed Identity Documentation](managed-identity.md) for the accepted blast-radius trade-off this implies.

## Detailed Role Assignments Table

| Principal | Role Definition Name | Role Definition ID (GUID) | Target Resource Scope | Reason / Purpose |
|---|---|---|---|---|
| **Shared Managed Identity** | `Storage Blob Data Contributor` | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` | Storage Account | Read/write access for application artifacts |
| **Shared Managed Identity** | `Key Vault Secrets User` | `4633458b-17de-408a-b874-0445c86b69e6` | Key Vault | Read secrets for AI connections and the Python Chat App |
| **Shared Managed Identity** | `Cognitive Services OpenAI User` | `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd` | Azure OpenAI Account | Authorize the Chat App to invoke model inference |
| **Shared Managed Identity** | `Cosmos DB Built-in Data Contributor` | `00000000-0000-0000-0000-000000000002` | Cosmos DB account SQL data plane | Read/write documents with Microsoft Entra authentication while local key auth is disabled |
| **Shared Managed Identity** | `Virtual Machine Contributor` | `9980e02c-c2be-4d73-94e8-173b1dc7cf3c` | Jumpbox VM | Read VM state and start the VM from the daily Automation runbook |
| **Deploying Identity** | `Key Vault Secrets Officer` | `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` | Key Vault | Write/sync secrets (VM admin password) during ARM deployment |
| **Admin Actors** | `Key Vault Administrator` | `00482a5a-887f-4fb3-b363-3b7fe8e74483` | Key Vault | Manage keys, secrets, and certificates for administrators |
| **Admin Actors** | `Key Vault Secrets Officer` | `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` | Key Vault | Manage secrets for administrators and first-run setup |
| **Admin Actors** | `Storage Blob Data Owner` | `b7e6dc6d-f1e8-4753-8033-0f276bb0955b` | Backing Storage Account | Full data-plane ownership of storage containers and blobs |
| **Admin Actors** | `Storage Account Contributor` | `17d1049b-9a84-46fb-8f53-869881c3d3ab` | Backing Storage Account | Manage the storage account control plane |
| **Admin Actors** | `Cognitive Services OpenAI Contributor` | `a001fd3d-188f-4b5d-821b-7da978bf7442` | Azure OpenAI Account | Full operations on OpenAI account and deployments |
| **Admin Actors** | `Cognitive Services Contributor` | `25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68` | Azure OpenAI Account | Manage the Cognitive Services account control plane |
| **Admin Actors** | `Foundry Owner`, `Foundry Project Manager` | Built-in role IDs resolved by the templates | Foundry account/project | Administrative access over Foundry assets and project configuration |
| **Admin Actors** | `Virtual Machine Administrator Login` | `1c0163c0-47e6-4577-8991-ea5c82e286e4` | Jumpbox VM | Administrator login access to the VM |
| **Admin Actors** | `Log Analytics Contributor` | `92aaf0da-9dab-42b6-94a3-d43ce8d16293` | Log Analytics Workspace | Workspace operations and query configuration |
| **Admin Actors** | `Monitoring Contributor` | `749f88d5-cbae-40b8-bcfc-e573ddc772fa` | Log Analytics Workspace | Manage monitoring settings and diagnostic configuration |
| **Admin Actors** | `Contributor` & `User Access Administrator` | `b24988ac-6180-42a0-ab88-20f7382dd24c`, `18d7d88d-d35e-4fb5-a5c3-7773c20a72d9` | Resource Groups | Full control-plane and authorization management |
| **User Actors** | `Key Vault Secrets User` & `Officer` | `4633458b-17de-408a-b874-0445c86b69e6`, `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` | Key Vault | Read and manage secrets |
| **User Actors** | `Key Vault Reader` | `21090545-7ca7-4776-b22c-e363652d74d2` | Key Vault | View vault and secret metadata |
| **User Actors** | `Storage Blob Data Contributor` | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` | Backing Storage Account | Read and write blob data |
| **User Actors** | `Cognitive Services OpenAI User` | `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd` | Azure OpenAI Account | Inference and model consumption |
| **User Actors** | `Cognitive Services User` | `a97b65f3-24c7-4388-baec-2e87135dc908` | Azure OpenAI Account | Read account metadata and list deployments |
| **User Actors** | `Foundry User`, `Foundry Agent Consumer` | Built-in role IDs resolved by the templates | Foundry project | Build and invoke project Agents |

The Foundry project system identity also receives Storage Blob Data Contributor/Owner, Cosmos DB Operator and SQL Data Contributor, Search Index Data Contributor, Search Service Contributor, and Cognitive Services User at their resource scopes.
| **User Actors** | `Virtual Machine User Login` | `fb879df8-f326-4884-b1cf-06f3ad86be52` | Jumpbox VM | Non-admin user login access to the VM |
| **User Actors** | `Log Analytics Reader` & `Monitoring Reader` | `73c42c96-874c-492b-b04d-ab87d138a893`, `43d0d8ad-25c7-4714-9337-8ba259a9fe05` | Log Analytics Workspace | Read telemetry and workspace logs |
| **User Actors** | `Reader` | `acdd72a7-3385-48ef-bd42-f606fba81ae7` | Resource Groups | View resources and configuration across resource groups |

## Key Invariants

1. **No Shared Keys or API Keys:** Local authentication is disabled on OpenAI and Cosmos DB, shared keys disabled on Storage, and access policies disabled on Key Vault in favor of Entra ID or service-native RBAC.
2. **Deterministic Role Assignment Names:** Role assignment resource names use deterministic GUIDs based on `guid(resourceGroup().id, scope.id, principalId, roleId)` to ensure idempotency across redeployments.
3. **Automation Isolation:** The Automation identity receives Virtual Machine Contributor on the individual VM and Network Contributor on the individual NSG. It has no Key Vault, Storage, OpenAI, subscription, or role-assignment access.

## Related Documentation

- [Managed Identity Documentation](managed-identity.md)
- [Key Vault Documentation](key-vault.md)
- [Storage Account Documentation](storage-account.md)
- [Azure OpenAI Documentation](azure-openai.md)
- [Cosmos DB Documentation](cosmos-db.md)
- [Documentation Index](index.md)
