# Azure DevOps pipelines

Consolidated multi-stage pipelines are provided with runtime parameter selection for `dev` and `uat`.

| Pipeline | Trigger | Purpose |
|---|---|---|
| `deploy.yml` | Manual | Security gate, planning (What-If), deployment, and validation for selected environment (`dev`/`uat`) |
| `cleanup.yml` | Manual | Preview (What-If) and guarded deletion of resource groups for selected environment (`dev`/`uat`) |

Each pipeline reads its variables from a variable group named `ai-infra-<environment>` because `variables/*.yaml` is intentionally untracked. The group must define:

| Variable | Purpose |
|---|---|
| `serviceConnection` | Azure service connection used by every `AzureCLI@2` task |
| `vmAdminPassword` | Protected secret passed to `-VmAdminPassword`; CI never prints it |
| `aiInfraCoreYaml` | Full contents of your `variables/core.yaml` |
| `aiInfraEnvYaml` | Full contents of your `variables/<environment>.yaml` |

`aiInfraCoreYaml` and `aiInfraEnvYaml` are surfaced to the scripts as `AI_INFRA_CORE_YAML` and `AI_INFRA_ENV_YAML`; `scripts/config.ps1` materializes them for the run only.

For in-depth architectural breakdown and stage details, see the [Azure DevOps Pipelines Documentation](../docs/azure-pipelines.md).

Update this README whenever a pipeline is added or its stages change; see [../.github/instructions/documentation-sync.instructions.md](../.github/instructions/documentation-sync.instructions.md).
