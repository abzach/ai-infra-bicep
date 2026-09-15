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

