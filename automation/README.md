# Azure Automation runbooks

Every top-level `*.ps1` file in this folder is validated, provisioned as a PowerShell 7.4 runbook, uploaded through Azure Resource Manager, and published by `scripts/deploy.ps1`.

| Runbook | Purpose | Schedule |
|---|---|---|
| `delete-rdp-deployer-rule.ps1` | Idempotently deletes only the temporary `allow-rdp-deployer` NSG rule | Weekly at `rdpDeployerCleanupScheduleTime` |
| `start-vm.ps1` | Starts the environment jumpbox idempotently by using the Automation user-assigned managed identity | Daily at `vmStartScheduleTime` |

Runbook file stems must start with a letter and contain only letters, numbers, hyphens, and underscores. Filenames must be unique without regard to case. Keep reusable files outside the top level because every top-level PowerShell file is published.

Runbooks must use managed identity authentication and must not contain credentials, tokens, subscription IDs, or tenant-specific values. Pass environment-specific values through job schedule parameters. Add only the resource-scoped RBAC permissions required by each runbook.

`deploy.ps1 -WhatIf` validates runbook source and previews infrastructure without uploading or publishing content. A normal deployment publishes changed source after Bicep succeeds.
