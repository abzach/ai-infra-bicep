# GitHub automation

GitHub Actions definitions for manual development deployment and cleanup.

- Deploy uses OIDC login, runs a non-mutating Bicep preview, deploys `dev`, and validates resources.
- Repository Copilot skill guidance lives in `copilot-instructions.md`, `copilot-skills-plan.md`, and path-specific files under `instructions/`.
- Cleanup previews deletion before invoking the guarded cleanup script.
- Configure repository secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, and `VM_ADMIN_PASSWORD`.
- The federated identity needs deployment permissions described in the root [README](../README.md).
- VM passwords are not printed in CI. The deployment workflow supplies `VM_ADMIN_PASSWORD` to `-VmAdminPassword`; retrieve and rotate it through your secret-management process.

## Copilot skill catalog

| Skill | File |
|---|---|
| Repository-wide working agreement | [copilot-instructions.md](copilot-instructions.md) |
| Skill brainstorm and implementation plan | [copilot-skills-plan.md](copilot-skills-plan.md) |
| Bicep service/module changes | [instructions/bicep-service-change.instructions.md](instructions/bicep-service-change.instructions.md) |
| Deployment orchestration changes | [instructions/deployment-orchestration.instructions.md](instructions/deployment-orchestration.instructions.md) |
| Security hardening/review | [instructions/security-review.instructions.md](instructions/security-review.instructions.md) |
| App bootstrap/runtime changes | [instructions/app-bootstrap.instructions.md](instructions/app-bootstrap.instructions.md) |
| Pipeline/workflow changes | [instructions/pipeline-workflow.instructions.md](instructions/pipeline-workflow.instructions.md) |
| Validation and troubleshooting | [instructions/validation-troubleshooting.instructions.md](instructions/validation-troubleshooting.instructions.md) |

See the [workflow index](workflows/index.md).
