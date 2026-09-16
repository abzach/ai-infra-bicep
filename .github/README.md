# GitHub automation

GitHub Actions definitions for automated CI testing, development deployment, and cleanup.

- CI tests (`ci.yml`) automatically run on push to `main` and PRs: static analysis, Bicep build and lint, IaC security scan, AI safety & prompt injection scanner, and Python syntax checks.
- Deploy uses OIDC login secret names configured in the selected environment YAML, runs a non-mutating Bicep preview, deploys the selected environment (`dev`/`uat`), and validates resources.
- Repository Copilot skill guidance lives in `copilot-instructions.md`, `copilot-skills-plan.md`, and path-specific files under `instructions/`.
- Architecture and security documentation lives in the [`docs/`](../docs/README.md) catalog.
- The official Bicep MCP server is registered in [`.mcp.json`](../.mcp.json) and [`.vscode/mcp.json`](../.vscode/mcp.json); see `instructions/bicep-mcp-server.instructions.md` for which Bicep tasks should use it.
- Cleanup resolves OIDC login secret names from the selected environment YAML, previews deletion, then invokes the guarded cleanup script for that environment.
- Configure repository secrets named by `githubAzureClientIdSecretName`, `githubAzureTenantIdSecretName`, and `githubAzureSubscriptionIdSecretName` in `variables/<env>.yaml`; the default names are `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`. Also configure `VM_ADMIN_PASSWORD`.
- The federated identity needs deployment permissions described in the root [README](../README.md).
- VM passwords are not printed in CI. The deployment workflow supplies `VM_ADMIN_PASSWORD` to `-VmAdminPassword`; retrieve and rotate it through your secret-management process.

## Copilot skill catalog

| Skill | File |
|---|---|
| Repository-wide working agreement | [copilot-instructions.md](copilot-instructions.md) |
| Skill brainstorm and implementation plan | [copilot-skills-plan.md](copilot-skills-plan.md) |
| Bicep service/module changes | [instructions/bicep-service-change.instructions.md](instructions/bicep-service-change.instructions.md) |
| Bicep MCP server usage | [instructions/bicep-mcp-server.instructions.md](instructions/bicep-mcp-server.instructions.md) |
| Deployment orchestration changes | [instructions/deployment-orchestration.instructions.md](instructions/deployment-orchestration.instructions.md) |
| Security hardening/review | [instructions/security-review.instructions.md](instructions/security-review.instructions.md) |
| App bootstrap/runtime changes | [instructions/app-bootstrap.instructions.md](instructions/app-bootstrap.instructions.md) |
| Pipeline/workflow changes | [instructions/pipeline-workflow.instructions.md](instructions/pipeline-workflow.instructions.md) |
| Validation and troubleshooting | [instructions/validation-troubleshooting.instructions.md](instructions/validation-troubleshooting.instructions.md) |
| Documentation sync | [instructions/documentation-sync.instructions.md](instructions/documentation-sync.instructions.md) |

See the [workflow index](workflows/index.md).

This document must stay current: update it whenever GitHub automation, the skill catalog, or MCP server registration changes.
