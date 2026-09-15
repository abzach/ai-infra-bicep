# Azure Key Vault

This document details the configuration, security controls, and secret management for Azure Key Vault provisioned by `bicep/modules/keyvault.bicep`.

## Resource Overview

Azure Key Vault provides secure storage for environment configuration, secrets, VM local administrator credentials, and Azure Disk Encryption keys. It enforces modern Azure RBAC authorization and disables legacy access policies.

- **Resource Name:** `kv-<baseName>-<environmentSuffix>-<nameSuffix>` (Globally unique, 3-24 characters)
- **Resource Type:** `Microsoft.KeyVault/vaults@2023-07-01`
- **SKU:** `Standard` (Family `A`)

## Important Configuration Settings

| Setting / Property | Configured Value | Description / Security Impact |
|---|---|---|
| **SKU Family & Name** | `A` / `standard` | Standard Key Vault tier |
| **Enable RBAC Authorization** | `true` | Enforces Azure RBAC; legacy vault access policies are ignored |
| **Access Policies** | `[]` (Empty) | Enforces zero legacy access policies |
| **Public Network Access** | `Disabled` | Blocks direct internet ingress |
| **Network ACLs Default Action** | `Deny` | Blocks all traffic outside configured private endpoints |
| **Network ACLs Bypass** | `AzureServices` | Allows trusted Azure platform service interactions |
| **Enable Soft-Delete** | `true` | Prevents permanent accidental secret loss |
| **Soft-Delete Retention** | `7` days (7-90 allowed) | Retention window for soft-deleted items |
| **Enabled for Deployment** | `true` | Allows VM resource provider to retrieve secrets |
| **Enabled for Template Deployment** | `true` | Allows ARM/Bicep template deployments to reference secrets |
| **Enabled for Disk Encryption** | `true` | Allows Azure Disk Encryption to consume secrets and keys |

## Secret Provisioning & Access

- **ARM Secret Writes:** Deployments write the Jumpbox VM administrator password into Key Vault directly using ARM template resources (`Microsoft.KeyVault/vaults/secrets@2023-07-01`) rather than data-plane commands.
- **Secrets Officer Role:** The deploying identity is granted `Key Vault Secrets Officer` during deployment to write secrets securely.
- **Managed Identity Access:** The VM managed identity and AI Hub managed identity are granted `Key Vault Secrets User` role to read secrets via private endpoint over `privatelink.vaultcore.azure.net`.

## Related Documentation

- [Private Endpoints Documentation](private-endpoints.md)
- [Role-Based Access Control Documentation](role-based-access-control.md)
- [Virtual Machine Documentation](virtual-machine.md)
- [Documentation Index](index.md)
