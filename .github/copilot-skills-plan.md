# GitHub Copilot skills plan

## Brainstormed skills for this codebase

| Skill | Why it is useful here | Implemented as |
|---|---|---|
| Bicep service/module change | New Azure services must preserve naming, tags, private networking, outputs, and module orchestration. | `instructions/bicep-service-change.instructions.md` |
| Bicep MCP server usage | The official Bicep MCP server gives authoritative resource schemas, best practices, diagnostics, formatting, AVM lookup, deployment previews, and ARM decompilation instead of guesswork. | `instructions/bicep-mcp-server.instructions.md`, registered in `.mcp.json` and `.vscode/mcp.json` |
| Deployment orchestrator change | `deploy.ps1` coordinates Azure context, idempotency, Bicep, secrets, diagnostics, app bootstrap, and credential handoff. | `instructions/deployment-orchestration.instructions.md` |
| Security hardening/review | The stack has strict invariants around public access, RBAC, diagnostics, VM security, and secret handling. | `instructions/security-review.instructions.md` |
| App bootstrap/runtime change | Python and VM bootstrap changes must keep managed identity auth and private Key Vault/OpenAI access intact. | `instructions/app-bootstrap.instructions.md` |
| Pipeline/workflow change | GitHub Actions and Azure DevOps must run equivalent plan, deploy, and validation behavior without leaking secrets. | `instructions/pipeline-workflow.instructions.md` |
| Validation and troubleshooting | Deploy fixes normally require static scans plus live Validate/Smoke/ChatDual follow-up when an environment exists. | `instructions/validation-troubleshooting.instructions.md` |
| Documentation sync | Docs across this repo describe fast-moving Bicep/scripts/app/pipeline behavior; without an explicit rule they drift out of date. | `instructions/documentation-sync.instructions.md` |

## Bicep work that benefits from the Bicep MCP server

- Adding a new Azure service/module: confirm exact resource type names and schemas instead of guessing.
- Changing an API version or resource property: verify the new schema before editing.
- Writing or reviewing secure defaults: check current Bicep best practices.
- Refactoring module wiring/outputs/parameters: trace references before moving things.
- Formatting `.bicep` files and running extra diagnostics beyond `az bicep build`/`lint`.
- Checking whether an Azure Verified Module (AVM) exists before hand-rolling a new module.
- Previewing a deployment/parameter change before running `-WhatIf` against a live subscription.
- Converting externally sourced ARM JSON (templates or parameters) into this repo's Bicep style.

See `instructions/bicep-mcp-server.instructions.md` for the full mapping and usage notes.

## Implementation plan

1. Add repository-wide Copilot instructions so GitHub Copilot and coding agents understand the deployment model, security posture, and required validation.
2. Add path-specific instruction files for each high-value skill area so guidance is scoped to the files being changed.
3. Document the skill catalog in `.github/README.md` and link it from `.github/index.md`.
4. Validate Markdown and source changes with the existing static Bicep and security checks plus PowerShell parsing.
5. Register the official Bicep MCP server (`.mcp.json`, `.vscode/mcp.json`) and add `bicep-mcp-server.instructions.md` mapping Bicep work to its tools.
6. Require every instruction file to include a "Keep this skill current" section so skills self-improve as they are used.
7. Require documentation to stay current with code via `documentation-sync.instructions.md` and pointer notes in affected READMEs.

## Operating model for future changes

- Start from the relevant skill file and the nearest `AGENTS.md`.
- Read the matching YAML, script, template, module, workflow, and docs before editing.
- Implement only the requested change, but wire every affected surface.
- Validate locally; for deployed-resource fixes, run `-WhatIf` before applying and follow with live tests.
- Use the Bicep MCP server for any Bicep schema, best-practice, diagnostics, formatting, or AVM lookup task.
- If a skill file is missing a step you needed, update it before finishing (see each file's "Keep this skill current" section).
- Update every doc affected by the change in the same change (see `instructions/documentation-sync.instructions.md`).

