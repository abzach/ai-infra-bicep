# Azure Log Analytics Workspace

This document covers the configuration, retention rules, and diagnostic ingestion settings for the Log Analytics workspace provisioned by `bicep/modules/loganalytics.bicep`.

## Resource Overview

The Log Analytics workspace collects operational telemetry, audit events, access logs, and performance metrics from Azure OpenAI, Azure AI Foundry Hub, and the Jumpbox VM.

- **Resource Name:** `law-<baseName>-<environmentSuffix>-<nameSuffix>`
- **Resource Type:** `Microsoft.OperationalInsights/workspaces@2023-09-01`
- **SKU:** `PerGB2018`

## Important Configuration Settings

| Setting / Property | Configured Value | Description / Operational Impact |
|---|---|---|
| **SKU Name** | `PerGB2018` | Standard Pay-As-You-Go ingestion model |
| **Data Retention** | `30` days (configurable 30-730) | Retention window for indexed log data (`retentionInDays`) |
| **Access Control Mode** | `enableLogAccessUsingOnlyResourcePermissions: true` | Enforces resource-context RBAC for querying logs |
| **Daily Ingestion Cap** | `0.5 GB` (configured via YAML) | Protects against runaway log ingestion costs |

## Ingested Diagnostic Sinks

The workspace acts as the central destination for diagnostic settings configured across the infrastructure:

| Source Resource | Diagnostic Setting Name | Ingested Categories |
|---|---|---|
| **Azure OpenAI Account** | `send-to-law` | `allLogs` (Audit, RequestResponse, Trace), `AllMetrics` |
| **Azure AI Foundry Hub** | `send-to-law` | `allLogs` (App, Workspace, Execution), `AllMetrics` |
| **Jumpbox VM** | `AzureMonitorWindowsAgent` | Windows Event Logs, Performance Counters, Heartbeats |

## Example KQL Verification Queries

```kql
// Verify Azure OpenAI API requests and token activity
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| order by TimeGenerated desc
| take 50

// Check VM Heartbeat telemetry
Heartbeat
| summarize LastCall = max(TimeGenerated) by Computer
```

## Related Documentation

- [Azure OpenAI Documentation](azure-openai.md)
- [AI Hub Documentation](ai-hub.md)
- [Virtual Machine Documentation](virtual-machine.md)
- [Documentation Index](index.md)
