# Bicep infrastructure

Standalone Bicep for the subscription-scope Azure AI Foundry deployment.

- `templates/main.bicep` creates environment resource groups and orchestrates modules, including explicit dependencies so actor RBAC assignments wait for optional target resources before applying roles.
- `modules/` contains network, identity, security, observability, private Microsoft Foundry Agent Service, Azure AI Search, Azure OpenAI, Storage, Key Vault, Static Web Apps, Cosmos DB, API Management, PostgreSQL, VM, and Azure Automation resources. Foundry uses a dedicated delegated subnet (or an optional recovery subnet when the original retains a service link), private endpoints, AAD backing-resource connections, and project-scoped Agent RBAC.
- `templates/main.bicepparam` is a documented example parameter file; `deploy.ps1` generates the effective secure parameter JSON at runtime.
- In-depth resource configurations and tabular specifications are documented in the [Architecture Documentation](../docs/README.md).

Build and lint all templates with:

```powershell
.\scripts\test.ps1 -Mode Static
```

Do not commit generated JSON output or parameter files containing secrets.

This README must stay current with `bicep/**`. Update it in the same change as any module addition/removal; see [../.github/instructions/documentation-sync.instructions.md](../.github/instructions/documentation-sync.instructions.md). For resource schema lookups, best practices, diagnostics, and formatting, use the Bicep MCP server described in [../.github/instructions/bicep-mcp-server.instructions.md](../.github/instructions/bicep-mcp-server.instructions.md).
