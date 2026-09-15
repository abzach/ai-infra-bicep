# Agent guidance

## Repository purpose

This repository deploys a private Azure AI Foundry learning environment with standalone Bicep and PowerShell. It includes Azure OpenAI model deployments, AI Hub and Project workspaces, private networking, Key Vault, Storage, Log Analytics, managed identities, and a Windows jumpbox that hosts the Python chat application.

## Source map

- `bicep/templates/main.bicep` is the subscription-scope entry point.
- `bicep/modules/` contains resource-focused Bicep modules.
- `variables/core.yaml` contains shared non-SKU defaults.
- `variables/dev.yaml` and `variables/uat.yaml` contain environment naming, identity, SKU, capacity, and pipeline values.
- `scripts/config.ps1` merges and validates YAML configuration.
- `scripts/deploy.ps1` validates Azure context, exits early for already-current environments, deploys Bicep when needed, writes Key Vault secrets through ARM, bootstraps the VM through Run Command, and applies the VM password.
- `scripts/test.ps1` provides `Static`, `Validate`, `Smoke`, and `ChatDual` modes.
- `scripts/security-scan.ps1` validates generated IaC security invariants.
- `scripts/cleanup.ps1` deletes only tag-validated environment resource groups.
- `app/` contains the managed-identity Python chat and connectivity test.
- `.mcp.json` and `.vscode/mcp.json` register the official Bicep MCP server (`Azure.Bicep.McpServer` via `dnx`) for schema lookups, best practices, diagnostics, formatting, AVM metadata, and ARM decompilation; see `.github/instructions/bicep-mcp-server.instructions.md`.

## Required invariants

- Keep Key Vault, Storage, Azure OpenAI, AI Hub, and AI Project public network access disabled.
- Keep Storage shared-key access, blob public access, and Azure OpenAI local authentication disabled.
- Use private endpoints and private DNS for service data-plane access.
- Use resource-scoped data-plane RBAC. The VM needs only `Key Vault Secrets User` and `Cognitive Services OpenAI User`; it does not need Storage access for bootstrap.
- Keep Trusted Launch, Secure Boot, vTPM, and `Windows_Client` licensing on the selected Windows image.
- Restrict RDP to explicitly supplied/detected CIDRs and retain the deny-all RDP rule.
- Do not reintroduce workstation Key Vault or Storage data-plane operations. The deployment host writes secret resources through ARM; app files reach the VM through Run Command.
- Never print or persist VM credentials in CI logs or workspaces. Local credential output belongs only under ignored `.local/`.

## Configuration rules

- Put shared behavior and non-SKU defaults in `variables/core.yaml`.
- Put every SKU, capacity, environment identity, and environment naming choice in `variables/dev.yaml` or `variables/uat.yaml`.
- Add an inline comment to every YAML variable describing purpose and allowed values.
- Wire new settings through `scripts/config.ps1`, `bicep/templates/main.bicep`, affected modules, `main.bicepparam`, tests, and documentation.
- Keep the deployment no-op guard accurate by ensuring changes that alter desired infrastructure or deployed app behavior are included in the `desiredStateHash` inputs in `scripts/deploy.ps1`.
- Preserve existing naming constraints, including the subscription-derived four-character suffix.

## Safe workflow

1. Read the relevant YAML, script, template, and module before editing.
2. Use `.\scripts\deploy.ps1 <dev|uat> -WhatIf` for a non-mutating Azure preview. Normal deploy reruns should exit early when `desiredStateHash` is current; use `-ForceRedeploy` only when an intentional refresh is required.
3. Never run `scripts/cleanup.ps1` without explicit authorization; use `-WhatIf` first.
4. Do not commit `.azure/`, `.local/`, `.env`, credentials, generated JSON, logs, or machine-local notes.
5. Do not expose passwords, tokens, tenant-specific secrets, or generated credential files in commits or CI output.

## Validation

Run the smallest applicable checks and finish with:

```powershell
.\scripts\test.ps1 -Mode Static
.\scripts\security-scan.ps1
```

For a deployed environment:

```powershell
.\scripts\test.ps1 -Mode Validate -EnvironmentSuffix dev
.\scripts\test.ps1 -Mode Smoke -EnvironmentSuffix dev
.\scripts\test.ps1 -Mode ChatDual -EnvironmentSuffix dev
```

Also parse changed PowerShell files, run `git diff --check`, and inspect `git status --short`. A successful deployment must be followed by live RBAC, private-network, VM bootstrap, and model-call verification.

## Documentation

Every maintained source folder contains `README.md` for detail and `index.md` for navigation. Update both when responsibilities or file inventories change. Use repository-relative links and never place machine-specific paths, subscription IDs, credentials, or deployment-plan evidence in tracked documentation.

Documentation updates are mandatory, not optional: whenever you change Bicep, scripts, app code, workflows/pipelines, variables, or instruction files, update every doc that describes the changed behavior in the same change. Treat a stale doc as a bug caused by that change. See `.github/instructions/documentation-sync.instructions.md` for the full doc-to-code mapping and rules.
