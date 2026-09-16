# Azure AI Foundry Hub

This document details the configuration, security posture, diagnostic routing, and workspace connection for Azure AI Foundry Hub provisioned by `bicep/modules/aihub.bicep`.

## Deployment flag

This component is controlled by `deployAiFoundry` in your environment YAML. When set to `false`, the next `scripts/deploy.ps1` run removes the AI Project, the AI Hub, and the hub private endpoint.

## Resource Overview

The AI Foundry Hub workspace serves as the centralized management, governance, security, and resource-sharing control plane for AI teams and child AI Projects.

- **Resource Name:** `hub-<baseName>-<environmentSuffix>-<nameSuffix>`
- **Resource Type:** `Microsoft.MachineLearningServices/workspaces@2024-10-01`
- **Kind:** `Hub`
- **SKU:** `Basic`

## Important Configuration Settings

| Setting / Property | Configured Value | Description / Security Impact |
|---|---|---|
| **Kind** | `Hub` | Configures the workspace as an Azure AI Foundry Hub |
| **SKU Name** | `Basic` | AI workspace SKU |
| **Identity Type** | `UserAssigned` | Uses dedicated User-Assigned Identity (`mi-...-hub-...`) |
| **Primary Managed Identity** | `identityId` | Backing identity for cross-resource authentication |
| **Public Network Access** | `Disabled` | Blocks direct public internet access |
| **Allow Public Access When Behind VNet** | `false` | Disables public workspace access even when behind VNet |
| **Storage Account Integration** | `storageAccountResourceId` | Attached to private Storage Account (`st...`) |
| **Key Vault Integration** | `keyVaultResourceId` | Attached to private Key Vault (`kv-...`) |
| **Diagnostic Settings** | `send-to-law` | Routes `allLogs` and `AllMetrics` to Log Analytics Workspace (`law-...`) |

## Workspace Connection to Azure OpenAI

The module automatically creates a native workspace connection to the provisioned Azure OpenAI account:

| Connection Property | Configured Value | Description |
|---|---|---|
| **Connection Name** | `openai-connection` | Internal connection identifier |
| **Resource Type** | `Microsoft.MachineLearningServices/workspaces/connections@2024-10-01` | Hub child resource |
| **Category** | `AzureOpenAI` | Connected AI service category |
| **Target** | `openAiEndpoint` | Azure OpenAI endpoint URL |
| **Auth Type** | `AAD` | Uses Microsoft Entra ID (token-based), no shared API keys |
| **Shared to All** | `true` | Inherited automatically by child AI Projects |
| **Metadata ApiType** | `Azure` | Cognitive Services API type |
| **Metadata ApiVersion** | `2024-10-01-preview` | Cognitive Services management API version |

## Related Documentation

- [AI Project Documentation](ai-project.md)
- [Azure OpenAI Documentation](azure-openai.md)
- [Managed Identity Documentation](managed-identity.md)
- [Private Endpoints Documentation](private-endpoints.md)
- [Log Analytics Documentation](log-analytics.md)
- [Documentation Index](index.md)
