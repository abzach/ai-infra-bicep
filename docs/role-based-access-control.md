# Role-Based Access Control (RBAC)

This document details all Azure RBAC role assignments provisioned by `bicep/modules/managedidentityroles.bicep`, `keyvault.bicep`, and `storageaccount.bicep`.

## RBAC Matrix & Principles

The environment follows strict least-privilege principles. No service or identity is granted broad subscription-wide permissions. All role assignments are scoped directly to the target Azure resource.

```
Principal                          Scope               Role Definition Name
─────────────────────────────────────────────────────────────────────────────────────────────
AI Hub Managed Identity            Storage Account     Storage Blob Data Contributor
AI Hub Managed Identity            Key Vault           Key Vault Secrets User
AI Hub Managed Identity            Azure OpenAI        Cognitive Services OpenAI User
─────────────────────────────────────────────────────────────────────────────────────────────
VM Managed Identity                Key Vault           Key Vault Secrets User
VM Managed Identity                Azure OpenAI        Cognitive Services OpenAI User
─────────────────────────────────────────────────────────────────────────────────────────────
Deploying Identity (SP/User)       Key Vault           Key Vault Secrets Officer
─────────────────────────────────────────────────────────────────────────────────────────────
Admin User Object IDs              Key Vault           Key Vault Administrator
Admin User Object IDs              Storage Account     Storage Blob Data Contributor
```

## Detailed Role Assignments Table

| Principal | Role Definition Name | Role Definition ID (GUID) | Target Resource Scope | Reason / Purpose |
|---|---|---|---|---|
| **AI Hub Identity** | `Storage Blob Data Contributor` | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` | Backing Storage Account | Read/write access to AI project experiment and model artifacts |
| **AI Hub Identity** | `Key Vault Secrets User` | `4633458b-17de-408a-b874-0445c86b69e6` | Key Vault | Read secrets for AI connection configurations |
| **AI Hub Identity** | `Cognitive Services OpenAI User` | `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd` | Azure OpenAI Account | Authorize AI Hub connection to OpenAI endpoints via AAD |
| **VM Managed Identity** | `Key Vault Secrets User` | `4633458b-17de-408a-b874-0445c86b69e6` | Key Vault | Read VM admin credentials and configuration secrets |
| **VM Managed Identity** | `Cognitive Services OpenAI User` | `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd` | Azure OpenAI Account | Authorize Python Chat App to invoke model inference |
| **Deploying Identity** | `Key Vault Secrets Officer` | `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` | Key Vault | Write/sync secrets (VM admin password) during ARM deployment |
| **Admin Object IDs** | `Key Vault Administrator` | `00482a5a-887f-4fb3-b363-3b7fe8e74483` | Key Vault | Manage keys, secrets, and certificates for Entra administrators |
| **Admin Object IDs** | `Storage Blob Data Contributor` | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` | Backing Storage Account | Manage blob data and container artifacts |

## Key Invariants

1. **No Shared Keys or API Keys:** Local authentication is disabled on OpenAI, shared keys disabled on Storage, and access policies disabled on Key Vault in favor of pure Entra ID RBAC.
2. **Deterministic Role Assignment Names:** Role assignment resource names use deterministic GUIDs based on `guid(resourceGroup().id, scope.id, principalId, roleId)` to ensure idempotency across redeployments.

## Related Documentation

- [Managed Identity Documentation](managed-identity.md)
- [Key Vault Documentation](key-vault.md)
- [Storage Account Documentation](storage-account.md)
- [Azure OpenAI Documentation](azure-openai.md)
- [Documentation Index](index.md)
