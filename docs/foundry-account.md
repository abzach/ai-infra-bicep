# Microsoft Foundry Account and Agent Service

The deployment creates a `Microsoft.CognitiveServices/accounts` resource with `kind: AIServices`, plus a child Foundry project and Standard Agent Service capability host. This resource model is supported by the current Microsoft Foundry portal and replaces the legacy Azure Machine Learning Hub/Project workspaces.

## Deployment lifecycle

`deployAiFoundry` controls the Foundry account, child project, Azure AI Search, private endpoints, DNS zones, Agent subnet, connections, and capability host. A deployment validates the replacement account, project, capability host, and model deployments before purging the legacy Hub and Project.

The separate Azure OpenAI account remains deployed because the jumpbox chat application uses its endpoint and managed-identity authentication.

## Security configuration

| Setting | Value |
|---|---|
| Kind | `AIServices` |
| SKU | `S0` |
| Public network access | Disabled |
| Local/API-key authentication | Disabled |
| Network ACL default action | Deny |
| Agent network injection | Existing VNet, dedicated `agent` subnet or optional `agent-recovery` subnet when the original is still linked |
| Identity | System-assigned |
| Diagnostics | Log Analytics when `enableAuditDiagnostics` is enabled |

The account private endpoint registers `privatelink.services.ai.azure.com`, `privatelink.cognitiveservices.azure.com`, and `privatelink.openai.azure.com`.
After account recreation, a disconnected private endpoint is removed before deployment so Bicep can create a connected replacement.

## Agent backing resources

The child project uses AAD connections to Storage for Agent files, Cosmos DB for thread state, and Azure AI Search for vector stores. The project capability host binds those connections with `capabilityHostKind: Agents`.

## Related documentation

- [Foundry Project](ai-project.md)
- [Azure AI Search](ai-search.md)
- [Private Endpoints](private-endpoints.md)
- [Role-Based Access Control](role-based-access-control.md)