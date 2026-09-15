# Azure OpenAI Service & Model Deployments

This document details the configuration, security controls, diagnostic logging, and model deployments provisioned by `bicep/modules/openai.bicep`.

## Resource Overview

Azure OpenAI Service provides the large language model APIs for the terminal chat application and AI Foundry project experiments. It provisions two distinct model deployments in parallel:

- **Resource Name:** `oai-<baseName>-<environmentSuffix>-<nameSuffix>`
- **Resource Type:** `Microsoft.CognitiveServices/accounts@2024-10-01`
- **Kind:** `OpenAI`
- **SKU:** `S0`

## Important Configuration Settings

| Setting / Property | Configured Value | Description / Security Impact |
|---|---|---|
| **SKU Name** | `S0` | Standard Cognitive Services tier |
| **Custom Subdomain Name** | `oai-<baseName>-<env>-<suffix>` | Required for private endpoint and Entra ID authentication |
| **Disable Local Auth** | `true` | Enforces Entra ID authentication; disables API keys completely |
| **Public Network Access** | `Disabled` | Blocks public internet requests to endpoint |
| **Network ACLs Default Action** | `Deny` | Rejects all incoming traffic outside private links |
| **Diagnostic Settings** | `send-to-law` | Routes `allLogs` and `AllMetrics` to Log Analytics Workspace (`law-...`) |

## Model Deployments

The environment deploys two models in parallel to enable multi-persona evaluation (concise developer persona vs. architecture persona) in the chat application:

| Model Deployment Role | Deployment Alias / Name | Model Catalog Name | Model Version | Provisioning SKU | TPM Capacity (`capacityK`) |
|---|---|---|---|---|---|
| **Primary Model** | `gpt-4-1-mini` | `gpt-4.1-mini` | `2025-04-14` | `GlobalStandard` | `10` (Dev) / `20` (UAT) |
| **Secondary Model** | `gpt-4-1-nano` | `gpt-4.1-nano` | `2025-04-14` | `GlobalStandard` | `8` (Dev) / `10` (UAT) |

### Deployment Dependency
The secondary model deployment includes an explicit Bicep `dependsOn: [primaryModelDeployment]` declaration to prevent concurrent deployment conflicts against the Azure Cognitive Services ARM provider.

## Authentication & Consumption

1. **Bearer Token Authentication:** Local API keys are strictly disabled (`disableLocalAuth: true`).
2. **Data-Plane RBAC:** Clients authenticate with Microsoft Entra ID and must have the `Cognitive Services OpenAI User` role (`5e0bd9bd-7b93-4f28-af87-19fc36ad61bd`).
3. **Private Ingress:** Accessible solely via the private endpoint (`oai-...-account-pe`) mapped to `privatelink.openai.azure.com`.

## Related Documentation

- [Private Endpoints Documentation](private-endpoints.md)
- [Role-Based Access Control Documentation](role-based-access-control.md)
- [Chat Application Documentation](chat-application.md)
- [Log Analytics Documentation](log-analytics.md)
- [Documentation Index](index.md)
