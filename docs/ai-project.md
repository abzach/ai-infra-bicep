# Azure AI Foundry Project

This document details the configuration and architecture for the child Azure AI Foundry Project provisioned by `bicep/modules/aiproject.bicep`.

## Deployment flag

This component is controlled by `deployAiFoundry` in your environment YAML, together with the parent AI Hub. When set to `false`, the project is removed before the hub.

## Resource Overview

The AI Foundry Project workspace provides the developer canvas for evaluating prompt flows, fine-tuning, building AI agents, and experimenting with models. It inherits connections, security policies, storage, and keys from its parent AI Hub.

- **Resource Name:** `proj-<baseName>-<environmentSuffix>-<nameSuffix>`
- **Resource Type:** `Microsoft.MachineLearningServices/workspaces@2024-10-01`
- **Kind:** `Project`
- **SKU:** `Basic`

## Important Configuration Settings

| Setting / Property | Configured Value | Description / Security Impact |
|---|---|---|
| **Kind** | `Project` | Configures the workspace as an Azure AI Foundry Project |
| **SKU Name** | `Basic` | Basic AI project tier |
| **Hub Resource ID** | `hubResourceId` | Links project directly to parent Hub workspace |
| **Identity Type** | `SystemAssigned` | Managed identity managed at project scope |
| **Public Network Access** | `Disabled` | Prevents unauthorized public internet data-plane access |
| **Allow Public Access When Behind VNet** | `false` | Enforces private access through VNet and private link |

## Shared Hub Resources

The AI Project inherits the following resources and capabilities directly from the parent AI Hub:
1. **Azure OpenAI Connection:** Pre-configured `openai-connection` using AAD auth.
2. **Backing Key Vault:** Secret storage for connection strings and workspace credentials.
3. **Backing Storage Account:** Blob and container storage for experiment tracking and dataset caching.
4. **Monitoring:** Diagnostic telemetry forwarded through Hub diagnostics.

## Related Documentation

- [AI Hub Documentation](ai-hub.md)
- [Azure OpenAI Documentation](azure-openai.md)
- [Storage Account Documentation](storage-account.md)
- [Key Vault Documentation](key-vault.md)
- [Documentation Index](index.md)
