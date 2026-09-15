# Azure DevOps pipelines

Consolidated multi-stage pipelines are provided with runtime parameter selection for `dev` and `uat`.

| Pipeline | Trigger | Purpose |
|---|---|---|
| `deploy.yml` | Manual | Security gate, planning (What-If), deployment, and validation for selected environment (`dev`/`uat`) |
| `cleanup.yml` | Manual | Preview (What-If) and guarded deletion of resource groups for selected environment (`dev`/`uat`) |

Each pipeline imports the matching environment variables from `variables/${{ parameters.environment }}.yaml` and uses its `serviceConnection`. Define `vmAdminPassword` as a protected secret variable or variable-group value. Deployment passes it to `-VmAdminPassword` and suppresses credential output in CI.

For in-depth architectural breakdown and stage details, see the [Azure DevOps Pipelines Documentation](../docs/azure-pipelines.md).

Update this README whenever a pipeline is added or its stages change; see [../.github/instructions/documentation-sync.instructions.md](../.github/instructions/documentation-sync.instructions.md).
