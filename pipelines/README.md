# Azure DevOps pipelines

Manual multi-stage pipelines are provided for `dev` and `uat`.

| Pipeline | Purpose |
|---|---|
| `deploy-dev.yml` | Static security gate, preview, deployment, and validation for dev |
| `deploy-uat.yml` | Static security gate, preview, deployment, and validation for uat |
| `cleanup-dev.yml` | Guarded deletion of dev resource groups |
| `cleanup-uat.yml` | Guarded deletion of uat resource groups |

Each pipeline imports the matching YAML under `variables/` and uses its `serviceConnection`. Define `vmAdminPassword` as a protected secret variable or variable-group value. Deployment passes it to `-VmAdminPassword` and suppresses credential output in CI.

Update this README whenever a pipeline is added or its stages change; see [../.github/instructions/documentation-sync.instructions.md](../.github/instructions/documentation-sync.instructions.md).
