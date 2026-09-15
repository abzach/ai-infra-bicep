# GitHub Copilot skills plan

## Brainstormed skills for this codebase

| Skill | Why it is useful here | Implemented as |
|---|---|---|
| Bicep service/module change | New Azure services must preserve naming, tags, private networking, outputs, and module orchestration. | `instructions/bicep-service-change.instructions.md` |
| Deployment orchestrator change | `deploy.ps1` coordinates Azure context, idempotency, Bicep, secrets, diagnostics, app bootstrap, and credential handoff. | `instructions/deployment-orchestration.instructions.md` |
| Security hardening/review | The stack has strict invariants around public access, RBAC, diagnostics, VM security, and secret handling. | `instructions/security-review.instructions.md` |
| App bootstrap/runtime change | Python and VM bootstrap changes must keep managed identity auth and private Key Vault/OpenAI access intact. | `instructions/app-bootstrap.instructions.md` |
| Pipeline/workflow change | GitHub Actions and Azure DevOps must run equivalent plan, deploy, and validation behavior without leaking secrets. | `instructions/pipeline-workflow.instructions.md` |
| Validation and troubleshooting | Deploy fixes normally require static scans plus live Validate/Smoke/ChatDual follow-up when an environment exists. | `instructions/validation-troubleshooting.instructions.md` |

## Implementation plan

1. Add repository-wide Copilot instructions so GitHub Copilot and coding agents understand the deployment model, security posture, and required validation.
2. Add path-specific instruction files for each high-value skill area so guidance is scoped to the files being changed.
3. Document the skill catalog in `.github/README.md` and link it from `.github/index.md`.
4. Validate Markdown and source changes with the existing static Bicep and security checks plus PowerShell parsing.

## Operating model for future changes

- Start from the relevant skill file and the nearest `AGENTS.md`.
- Read the matching YAML, script, template, module, workflow, and docs before editing.
- Implement only the requested change, but wire every affected surface.
- Validate locally; for deployed-resource fixes, run `-WhatIf` before applying and follow with live tests.

