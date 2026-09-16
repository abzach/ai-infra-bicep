# Bicep infrastructure

Standalone Bicep for the subscription-scope Azure AI Foundry deployment.

- `templates/main.bicep` creates environment resource groups and orchestrates modules.
- `modules/` contains network, identity, security, observability, AI, Storage, Key Vault, VM, and Azure Automation resources, including the optional public IP DNS label for the jumpbox.
- `templates/main.bicepparam` is a documented example parameter file; `deploy.ps1` generates the effective secure parameter JSON at runtime.
- In-depth resource configurations and tabular specifications are documented in the [Architecture Documentation](../docs/README.md).

Build and lint all templates with:

```powershell
.\scripts\test.ps1 -Mode Static
```

Do not commit generated JSON output or parameter files containing secrets.

This README must stay current with `bicep/**`. Update it in the same change as any module addition/removal; see [../.github/instructions/documentation-sync.instructions.md](../.github/instructions/documentation-sync.instructions.md). For resource schema lookups, best practices, diagnostics, and formatting, use the Bicep MCP server described in [../.github/instructions/bicep-mcp-server.instructions.md](../.github/instructions/bicep-mcp-server.instructions.md).
