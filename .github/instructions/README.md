# Copilot instruction skills

Path-specific instruction files in this folder capture recurring GitHub Copilot skills for this Azure AI Foundry infrastructure codebase. They help future code changes, reviews, and fixes follow the same conventions as the Bicep modules, deployment scripts, workflows, and Python app.

| Instruction file | Applies to | Purpose |
|---|---|---|
| `bicep-service-change.instructions.md` | Bicep and variable files | Add or modify Azure services without breaking naming, service tag limits, private networking, or security invariants |
| `bicep-mcp-server.instructions.md` | Bicep files and MCP config | Use the official Bicep MCP server tools for schema lookups, best practices, diagnostics, formatting, and ARM decompilation |
| `azure-mcp-server.instructions.md` | Bicep, scripts, variables, and MCP config | Use the Azure MCP server against the live subscription to diagnose failures, confirm supported SKUs/quotas/regions, and verify deployment flags, alongside the Bicep MCP server |
| `azure-rbac-preflight.instructions.md` | Deployment scripts and workflows | Keep the role-assignment write preflight self-remediating: detect, self-grant User Access Administrator, elevate when allowed, re-verify, then fail loudly |
| `local-configuration.instructions.md` | Variables, scripts, docs, and pipelines | Keep every user-specific value inside untracked `variables/*.yaml`, commit only `*.yaml.example` templates, and keep other files value-free |
| `deployment-orchestration.instructions.md` | Deployment and config scripts | Preserve idempotent deploy behavior, non-interactive Bicep updates, ordered runbook publication, ARM secret sync, VM bootstrap, and explicit error handling |
| `security-review.instructions.md` | Infrastructure, scripts, app, and pipelines | Review high-risk security posture, secret handling, and compiled ARM resource traversal |
| `app-bootstrap.instructions.md` | Python app and VM bootstrap files | Keep managed identity auth, Key Vault config flow, and app hash behavior intact |
| `pipeline-workflow.instructions.md` | GitHub Actions, Azure DevOps, and variables | Keep CI/CD stages aligned and secret-safe |
| `validation-troubleshooting.instructions.md` | Test, scan, deploy, cleanup, and docs | Select the right static/live validation and troubleshooting path |
| `documentation-sync.instructions.md` | Bicep, scripts, app, workflows, variables, and instruction files | Require doc updates in the same change as the code/config they describe |

Every instruction file above ends with a "Keep this skill current" section: when a task needs steps beyond what a skill file documents, update that file with what you learned before finishing.

See the [Copilot skills plan](../copilot-skills-plan.md) for the brainstorm and implementation rationale.
