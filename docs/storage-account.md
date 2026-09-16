# Azure Storage Account

This document covers the configuration, security controls, and blob services for the storage account provisioned by `bicep/modules/storageaccount.bicep`.

## Deployment flag

This component is controlled by `deployStorage` in your environment YAML. When set to `false`, the next `scripts/deploy.ps1` run removes the blob private endpoint and then the storage account. `deployAiFoundry` requires `deployStorage` because the AI Hub needs a backing storage account.

## Resource Overview

The storage account serves as the shared data plane for Azure AI Foundry Hub, storing workspace files, models, code artifacts, and dataset references. It is fully isolated with public network access disabled and private endpoint connectivity.

- **Resource Name:** `st<baseName><environmentSuffix><nameSuffix>` (Globally unique, 3-24 lowercase alphanumeric)
- **Resource Type:** `Microsoft.Storage/storageAccounts@2023-01-01`
- **Kind:** `StorageV2`

## Important Configuration Settings

| Setting / Property | Configured Value | Description / Security Impact |
|---|---|---|
| **SKU Name** | `Standard_LRS` (or GRS/ZRS) | Storage replication tier configured via YAML |
| **Access Tier** | `Hot` | Default access tier for active model and dataset access |
| **Minimum TLS Version** | `TLS1_2` | Enforces modern cipher suites and protocol version |
| **Supports HTTPS Only** | `true` | Restricts unencrypted HTTP traffic |
| **Allow Blob Public Access** | `false` | Blocks anonymous public read access to all containers and blobs |
| **Allow Shared Key Access** | `false` | Disables storage account keys; mandates Entra ID RBAC token auth |
| **Public Network Access** | `Disabled` | Prevents traffic from public IP addresses |
| **Network ACLs Default Action**| `Deny` | Rejects all incoming network traffic outside private links |
| **Network ACLs Bypass** | `AzureServices` | Allows trusted Azure platform service interactions |
| **Blob Soft-Delete Retention** | `7` days | Protects against accidental blob deletion |
| **Container Soft-Delete Retention** | `7` days | Protects against accidental container deletion |
| **Created Container Name** | `chatapp` | Dedicated private blob container (`publicAccess: None`) |

## Data-Plane Access & Connectivity

All access to the storage account occurs through:
1. **Private Endpoint:** `st<baseName><env><suffix>-blob-pe` connected to the `services` subnet (`10.0.1.0/24`).
2. **Private DNS:** `privatelink.blob.core.windows.net` resolving internally.
3. **Authentication:** Pure Entra ID authentication via `Storage Blob Data Contributor` role assignments for administrators and the AI Hub managed identity.

## Related Documentation

- [Private Endpoints Documentation](private-endpoints.md)
- [Role-Based Access Control Documentation](role-based-access-control.md)
- [AI Hub Documentation](ai-hub.md)
- [Documentation Index](index.md)
