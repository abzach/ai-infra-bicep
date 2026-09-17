---
applyTo: "scripts/test.ps1,scripts/scan.ps1,scripts/deploy.ps1,scripts/cleanup.ps1,README.md,AGENTS.md"
---

# Validation and troubleshooting

- For source-only infrastructure changes, run `.\scripts\test.ps1 -Mode Static` and `.\scripts\scan.ps1`.
- For deployed environment fixes, run `.\scripts\deploy.ps1 -EnvironmentSuffix dev -WhatIf` before applying changes.
- After a successful live deployment, run the relevant live checks: `Validate`, `Smoke`, and `ChatDual` as applicable.
- Parse changed PowerShell files before committing to catch syntax errors.
- Use `git diff --check` to catch whitespace issues.
- Do not run `scripts\cleanup.ps1` without explicit approval; use `-WhatIf` first.
- When troubleshooting, preserve evidence from Azure CLI errors and deployment outputs, but do not commit tenant IDs, subscription IDs, credentials, or local logs.
- `deploy.ps1`, `cleanup.ps1`, and `test.ps1` also write curated, secret-redacted troubleshooting messages to a git-ignored `.logs/ai-infra.log` (rolling over to `.logs/ai-infra.log.old` at 5 MB); check it first when a repro is hard to capture from the console, and never commit it.
- Use the Bicep MCP server's `get_bicep_file_diagnostics` to cross-check `.bicep` files before/alongside `test.ps1 -Mode Static`; see `bicep-mcp-server.instructions.md`.

## Keep this skill current

If this task needed steps beyond what is listed above, add them to this file before finishing so future validation/troubleshooting work benefits.

