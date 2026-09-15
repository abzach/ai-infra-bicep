---
applyTo: "**/*.bicep,**/*.bicepparam,scripts/**/*.ps1,app/**/*.py,app/requirements.txt,app/.env.example,.github/workflows/**/*.yml,pipelines/**/*.yml,variables/**/*.yaml,.github/instructions/**/*.md,.mcp.json,.vscode/mcp.json"
---

# Documentation must stay current

Documentation in this repository is part of the change, not optional follow-up narrative. Whenever you change code, configuration, or tooling covered by this instruction, update every Markdown doc that describes the changed behavior in the same change.

## Mandatory doc-to-code mapping

| If you change... | You must also update... |
|---|---|
| Any `bicep/modules/*.bicep` file or `bicep/templates/main.bicep` | `bicep/README.md`, `bicep/modules/README.md`, any affected `index.md`, and the relevant sections of the root `README.md` |
| `bicep/templates/main.bicepparam` | `bicep/templates/README.md` |
| `variables/core.yaml`, `variables/dev.yaml`, or `variables/uat.yaml` | `variables/README.md` and the configuration tables in the root `README.md` |
| `scripts/deploy.ps1`, `scripts/config.ps1`, `scripts/common.ps1`, `scripts/setup.ps1`, `scripts/test.ps1`, or `scripts/security-scan.ps1` | `scripts/README.md`, the deployment workflow diagram in the root `README.md`, and `AGENTS.md` |
| `app/*.py`, `app/requirements.txt`, or `app/.env.example` | `app/README.md` |
| `.github/workflows/*.yml` or `pipelines/*.yml` | `.github/README.md`, `.github/workflows/README.md`, `pipelines/README.md`, and relevant `docs/*.md` files |
| Any `.github/instructions/*.instructions.md` skill file | `.github/copilot-skills-plan.md` and `.github/instructions/README.md` |
| `.mcp.json` or `.vscode/mcp.json` | `.github/instructions/bicep-mcp-server.instructions.md` and any README describing available tooling |
| Adding, removing, or renaming a file in a maintained folder | that folder's `README.md`, `index.md`, and the `docs/` catalog |

## Rules

- Treat stale documentation as a bug caused by the change. If an edit makes any statement in a doc inaccurate, incomplete, or misleading, fix that doc before the task is done.
- Do not defer doc updates to a follow-up task; make them in the same change as the code they describe.
- Rewrite or remove documentation that no longer matches the implementation instead of leaving outdated text next to new behavior.
- Do not add machine-specific paths, subscription IDs, credentials, or deployment-plan evidence to any tracked doc.

## Keep this skill current

If you find a code-to-doc mapping that is missing from the table above, add it here after finishing the task so future changes update the right docs automatically.
