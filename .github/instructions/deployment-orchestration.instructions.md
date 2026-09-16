---
applyTo: "scripts/deploy.ps1,scripts/config.ps1,scripts/common.ps1"
---

# Deployment orchestration changes

- Preserve the early no-op path in `deploy.ps1`: if resources exist and the recorded `desiredStateHash` matches local desired state, exit before provider registration, role cleanup, Bicep deployment, secret sync, VM bootstrap, or password reset.
- Use Azure Resource Manager for Key Vault secret writes; do not require Key Vault data-plane access from the deployment host.
- Keep VM app transfer on Azure VM Run Command; do not reintroduce Storage data-plane upload from the workstation or CI runner.
- Surface failures explicitly with `Write-Error` or repository-standard warning output; do not hide Azure CLI failures behind success-shaped defaults.
- Keep CI behavior non-interactive. CI must pass `-VmAdminPassword` from a protected secret and must not print or write credentials.
- If a change intentionally needs to bypass no-op behavior, use `-ForceRedeploy` for infrastructure or `-ForceAppBootstrap` for app package refresh.
- Clean up generated parameter files, first-run scripts, and temporary packages on every exit path you add.
- Provision Automation runbook metadata and schedules in Bicep, but create job-schedule links only after `deploy.ps1` has uploaded and published the runbook.
- Keep Bicep CLI setup non-interactive: compare the installed Azure CLI-managed version with `az bicep list-versions`, upgrade when older, verify the result, and fail explicitly if installation or upgrade cannot complete.
- Update `scripts/README.md`, the deployment workflow diagram in the root `README.md`, and `AGENTS.md` in the same change; see `documentation-sync.instructions.md`.

## Keep this skill current

If this task needed steps beyond what is listed above, add them to this file before finishing so future orchestration changes benefit.

## Component deployment flags

`deployStorage`, `deployLogAnalytics`, `deployAiFoundry`, `deployVm`, and `deployAutomation` come from the environment YAML through `scripts/config.ps1`.

- Pass every flag into `$deploymentParameters` so Bicep can skip the module.
- Keep the pre-deploy removal pass in `deploy.ps1` in dependency order: private endpoints and children before their parents, and the jumpbox OS disk explicitly after `az vm delete`.
- Never make Key Vault, the virtual network, private DNS, Azure OpenAI, their private endpoints, or the managed identities removable. They hold deployment state or everything else depends on them.
- Keep `Test-EnterpriseDeploymentCurrent` flag-aware: assert enabled components exist and disabled components are absent, so flipping a flag always forces the deployment path.
- Gate post-deploy steps (Log Analytics daily cap, audit diagnostics, runbook publication, VM bootstrap, password handling) on the relevant flag.
- Add new cross-flag dependencies to the validation block in `scripts/config.ps1`, not to ad-hoc checks in `deploy.ps1`.

## VM password preservation

A rerun must never change a password the VM already has.

- Generate a new password only when one is supplied, when `-RotateVmPassword` is passed, when the VM does not exist, or when a Spot/Regular priority change will recreate the VM.
- Otherwise set `$preserveExistingVmPassword`, skip the Key Vault `vm-admin-password` sync and `az vm user update`, and report that the previous password still applies.
- The Bicep `@secure()` VM password parameter still needs a value in preserve mode; pass a throwaway value that is never applied or stored.
