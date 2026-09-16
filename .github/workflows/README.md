# GitHub workflows

Consolidated workflows with runtime environment choice (`dev` or `uat`):

| Workflow | Trigger | Inputs | Purpose |
|---|---|---|---|
| `ci.yml` | `push` (to `main`), `pull_request` (to `main`), manual | None | Automated free CI tests (Bicep build/lint, security scan, AI safety/prompt injection scan, Python check) |
| `deploy.yml` | `workflow_dispatch` (Manual) | `environment: [dev, uat]` | Preview (What-If), deploy Bicep infrastructure, and validate the environment |
| `cleanup.yml` | `workflow_dispatch` (Manual) | `environment: [dev, uat]` | Preview (What-If) and delete tag-validated resource groups |

Both workflows authenticate with GitHub OIDC. Before each login, they read the selected environment YAML from `AI_INFRA_ENV_YAML` and use its configured GitHub secret names for the client ID, tenant ID, and subscription ID. Cleanup is destructive after its preview job and should be protected with GitHub environments or equivalent approval controls.

Because `variables/*.yaml` is intentionally untracked, both workflows pass the configuration in as secrets:

| Secret | Purpose |
|---|---|
| `AI_INFRA_CORE_YAML` | Full contents of your `variables/core.yaml` |
| `AI_INFRA_ENV_YAML` | Full contents of your `variables/<environment>.yaml` |
| `VM_ADMIN_PASSWORD` | VM administrator password used by the deploy job |
| Secret names configured by `githubAzureClientIdSecretName`, `githubAzureTenantIdSecretName`, `githubAzureSubscriptionIdSecretName` | OIDC login values; defaults are `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` |

`scripts/config.ps1` writes the supplied YAML to `variables/` for the duration of the run only.

For detailed threat modeling and workflow architecture, see:
- [GitHub Actions Workflows Documentation](../../docs/github-actions.md)
- [CI/CD & Public Repository Security Documentation](../../docs/ci-cd-security.md)

Update this README whenever a workflow is added or its triggers/stages change; see [../instructions/documentation-sync.instructions.md](../instructions/documentation-sync.instructions.md).
