# Copilot repository instructions

This repository deploys a private Azure AI Foundry learning environment with Bicep, PowerShell, GitHub Actions, Azure DevOps pipelines, and a managed-identity Python chat app.

## Work style

- Preserve the secure-by-default posture: private endpoints, public network access disabled, Entra ID authentication, resource-scoped RBAC, Trusted Launch VM settings, and restricted RDP.
- Make source changes idempotent. A normal `.\scripts\deploy.ps1 -EnvironmentSuffix dev` rerun should avoid resource changes when the environment already matches the current desired state.
- Keep configuration layered: shared defaults in `variables/core.yaml`, environment-specific values in `variables/dev.yaml` or `variables/uat.yaml`.
- When adding or changing a setting, wire it through YAML configuration, `scripts/config.ps1`, `scripts/deploy.ps1`, `bicep/templates/main.bicep`, affected modules, tests, and docs.
- Do not use Key Vault or Storage data-plane operations from the deployment host. Deployment writes Key Vault secret resources through ARM and transfers app files through VM Run Command.
- Never print, persist, or commit secrets. Local credential handoff files must remain under ignored `.local/`.
- Update both `README.md` and `index.md` files when a maintained folder's responsibilities or inventory changes. Docs must stay current with the code that changed in the same change; see `instructions/documentation-sync.instructions.md`. Treat a stale doc as a bug in the change that caused it.
- For Bicep resource schemas, best practices, diagnostics, formatting, AVM lookup, or ARM decompilation, use the official Bicep MCP server registered in `.mcp.json`/`.vscode/mcp.json`; see `instructions/bicep-mcp-server.instructions.md` for which tool applies to which task.
- Every file under `instructions/*.instructions.md` is self-improving: if a task needs steps beyond what a skill documents, update that skill file with what you learned before finishing the task.

## Required validation

Use the smallest applicable check first, then finish infrastructure changes with:

```powershell
.\scripts\test.ps1 -Mode Static
.\scripts\security-scan.ps1
git diff --check
git --no-pager status --short
```

For live environment changes, preview with:

```powershell
.\scripts\deploy.ps1 -EnvironmentSuffix dev -WhatIf
```

Only run cleanup after explicit human authorization, and prefer `-WhatIf` first.

