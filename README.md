# Private Azure AI Foundry learning environment

This repository deploys a private Azure AI Foundry environment for learning,
prototyping, and development. It uses Bicep and PowerShell to create the
network, Azure OpenAI models, AI Hub and Project workspaces, Key Vault,
Storage, monitoring, managed identities, and an optional Windows jumpbox with
a terminal chat app.

The deployment is secure by default:

- Service public network access is disabled.
- Private endpoints and private DNS provide service connectivity.
- Entra ID and resource-scoped RBAC are used instead of service keys.
- The jumpbox uses Trusted Launch and RDP is restricted to the deployer IP.
- Local configuration and credentials are git-ignored.

This project is released under the [MIT License](LICENSE).

## Before you start

Install:

- [Git](https://git-scm.com/download/win)
- [Azure CLI 2.60 or later](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [PowerShell 7 or later](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)

The deploying identity needs **Owner**, or **Contributor** plus
**User Access Administrator**, at subscription scope. The deployment creates
resources and role assignments.

```powershell
git --version
az --version
$PSVersionTable.PSVersion
az login
```

## Deploy locally

1. Clone the repository and open PowerShell in its root folder.
2. Create local configuration from the tracked examples:

   ```powershell
   Copy-Item variables\core.yaml.example variables\core.yaml
   Copy-Item variables\dev.yaml.example variables\dev.yaml
   ```

3. Edit `variables\core.yaml` and `variables\dev.yaml`. At minimum, set a
   short `baseName` and an Entra object ID in `admin`. Keep these files local;
   they are intentionally ignored by Git.
4. Preview the deployment:

   ```powershell
   .\scripts\deploy.ps1 -EnvironmentSuffix dev -WhatIf
   ```

5. Deploy:

   ```powershell
   .\scripts\deploy.ps1 -EnvironmentSuffix dev
   ```

The same commands work for `uat` after creating `variables\uat.yaml` from its
example. A normal rerun exits without changes when the environment already
matches the desired state. VM passwords are preserved when possible; use
`-RotateVmPassword` only when an intentional rotation is required. Local
credential output is written only under the ignored `.local\` folder.

## Use the environment

When the jumpbox is enabled, connect with RDP from the approved source IP.
The `AI Chat` desktop shortcut starts the managed-identity Python chat app.
If first-run setup did not start, run:

```text
C:\ChatApp\first-run.ps1
```

For app commands, personas, connectivity tests, and troubleshooting, see
[app/README.md](app/README.md).

## CI/CD options

The repository includes both GitHub Actions and Azure DevOps pipelines:

- [GitHub Actions](.github/workflows/README.md)
- [Azure DevOps pipelines](pipelines/README.md)

Both workflows use OIDC where supported and keep configuration in protected
pipeline or repository secrets. Never commit `variables/*.yaml`, passwords,
tokens, generated credentials, or deployment state.

## Validation

Run the local checks before opening a pull request:

```powershell
.\scripts\test.ps1 -Mode Static
.\scripts\security-scan.ps1
git diff --check
```

For a deployed environment, use the applicable `Validate`, `Smoke`, and
`ChatDual` modes described in [scripts/README.md](scripts/README.md).
Cleanup is destructive; preview it first and run it only with explicit
authorization:

```powershell
.\scripts\cleanup.ps1 -EnvironmentSuffix dev -WhatIf
```

## Where to find more detail

- [Architecture documentation](docs/README.md)
- [Bicep infrastructure](bicep/README.md)
- [PowerShell automation](scripts/README.md)
- [Environment configuration](variables/README.md)
- [Application](app/README.md)
- [Repository map](index.md)
- [Contributor and coding-agent guidance](AGENTS.md)

Machine-specific deployment state, generated credentials, and local notes are
intentionally excluded from source control.
