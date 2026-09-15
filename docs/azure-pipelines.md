# Azure DevOps Pipelines

This document details the consolidated Azure DevOps YAML pipelines in `pipelines/`.

## Consolidated Architecture

The repository provides two unified multi-stage Azure DevOps pipelines featuring runtime parameters to select the environment (`dev` or `uat`), automatically loading the corresponding variable file (`variables/dev.yaml` or `variables/uat.yaml`):

1. **Deploy Pipeline (`pipelines/deploy.yml`):** Multi-stage orchestrator covering Static/Security Gates, Planning (What-If), Infrastructure Deployment, and Validation.
2. **Cleanup Pipeline (`pipelines/cleanup.yml`):** Two-stage deletion orchestrator with a What-If Preview stage followed by a guarded Force Destroy stage.

## Pipeline Overview

| Pipeline File | Trigger | Runtime Parameters | Imported Variables | Stages |
|---|---|---|---|---|
| `pipelines/deploy.yml` | Manual (`trigger: none`, `pr: none`) | `environment: [dev, uat]` | `../variables/${{ parameters.environment }}.yaml` | `Security` ➔ `Planning` ➔ `Deploy` ➔ `Validate` |
| `pipelines/cleanup.yml` | Manual (`trigger: none`, `pr: none`) | `environment: [dev, uat]` | `../variables/${{ parameters.environment }}.yaml` | `Preview` ➔ `Destroy` |

## Deploy Pipeline (`deploy.yml`) Stages

```
 ┌──────────────────────┐
 │   1. Security Gate   │  Build & lint Bicep (test.ps1 -Mode Static)
 └──────────┬───────────┘  Scan IaC template (security-scan.ps1)
            │
 ┌──────────▼───────────┐
 │   2. Planning Phase  │  Non-mutating ARM What-If preview (deploy.ps1 -WhatIf)
 └──────────┬───────────┘
            │
 ┌──────────▼───────────┐
 │   3. Deploy Phase    │  Bicep deployment, ARM secrets sync, VM Run Command bootstrap
 └──────────┬───────────┘
            │
 ┌──────────▼───────────┐
 │  4. Validate Phase   │  RBAC, networking, and OpenAI inference verification
 └──────────────────────┘
```

### Stage Configuration Breakdown

| Stage | Job Name | Tasks / Steps | Parameters / Arguments |
|---|---|---|---|
| **Security** | `StaticSecurityChecks` | `PowerShell@2` (Bicep build/lint), `PowerShell@2` (Security scan) | `-Mode Static`, `scripts/security-scan.ps1` |
| **Planning** | `WhatIf` | `AzureCLI@2` | `-EnvironmentSuffix ${{ parameters.environment }} -WhatIf` |
| **Deploy** | `Deploy` | `AzureCLI@2` | `-EnvironmentSuffix ${{ parameters.environment }} -VmAdminPassword $env:VM_ADMIN_PASSWORD` |
| **Validate** | `PostDeployTests` | `AzureCLI@2` | `-Mode Validate -EnvironmentSuffix ${{ parameters.environment }}` |

## Cleanup Pipeline (`cleanup.yml`) Stages

| Stage | Job Name | Task | Arguments | Purpose |
|---|---|---|---|---|
| **Preview** | `Preview` | `AzureCLI@2` | `-EnvironmentSuffix ${{ parameters.environment }} -WhatIf` | Lists targeted resource groups without deleting |
| **Destroy** | `Destroy` | `AzureCLI@2` | `-EnvironmentSuffix ${{ parameters.environment }} -Force` | Deletes tag-validated environment resource groups |

## Pipeline Variable Requirements

| Variable Name | Type | Description |
|---|---|---|
| `serviceConnection` | Plain text | Azure DevOps ARM Service Connection configured in `variables/dev.yaml` or `variables/uat.yaml` |
| `vmAdminPassword` | Secret Variable | Protected secret variable configured in Azure DevOps pipeline library |

## Related Documentation

- [CI/CD & Public Repository Security](ci-cd-security.md)
- [GitHub Actions Workflows Documentation](github-actions.md)
- [Documentation Index](index.md)
