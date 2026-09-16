# Azure Automation Account

## Purpose

The Automation Account publishes every top-level PowerShell script from `automation/` as a PowerShell 7.4 cloud runbook. The initial `start-vm` runbook starts the environment jumpbox daily at the `vmStartScheduleTime` and `vmStartScheduleTimeZone` configured in your local `variables/core.yaml`.

## Deployment flag

This component is controlled by `deployAutomation` in your environment YAML. When set to `false`, the next `scripts/deploy.ps1` run removes the Automation Account (with its runbooks, schedules, and job schedules) and the Automation managed identity, and runbook publication is skipped. `deployAutomation` requires `deployVm` because the `start-vm` runbook is scoped to the jumpbox VM.

## Identity and RBAC

The Automation Account uses the dedicated user-assigned identity `mi-<base>-automation-<env>-<suffix>`. The runbook selects that identity explicitly with `Connect-AzAccount -Identity -AccountId <client-id>`.

The identity receives Virtual Machine Contributor at the individual jumpbox VM scope. It receives no Key Vault, Storage, OpenAI, network, subscription, or role-assignment permissions.

## Deployment lifecycle

`scripts/deploy.ps1` validates and hashes every top-level `automation/*.ps1` file. Bicep provisions the identity, Automation Account, runtime environment, runbook metadata, schedule, and VM-scoped role assignment. After the deployment succeeds, `deploy.ps1` uploads and publishes each runbook through Azure Resource Manager and only then creates the job-schedule link. Azure rejects a job link when its runbook has no published version, so this ordering is mandatory.

What-if mode validates local scripts and previews the resources but does not upload or publish runbook content. Runbook source hashes are included in the environment desired-state hash, so source changes trigger deployment and publication while unchanged environments retain the normal no-op exit.

The Automation Account and runbooks receive the shared deployment tags. The runtime environment is intentionally untagged because Azure Automation limits runtime environments to three tags, fewer than the repository's required shared tag set.

## Adding a runbook

1. Add a top-level `automation/<name>.ps1` file.
2. Use a name that starts with a letter and contains only letters, numbers, hyphens, and underscores.
3. Authenticate with managed identity; do not embed credentials or environment identifiers.
4. Add only the resource-scoped role assignments the script needs.
5. Add the schedule in `bicep/modules/automation.bicep` and create its job-schedule link in the post-publication phase of `scripts/deploy.ps1` only if the runbook must run automatically.
6. Run the static and security checks before deployment.

Files below the top level are not automatically published.
