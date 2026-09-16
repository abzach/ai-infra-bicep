# Environment configuration

> **These YAML files are local-only.** `variables/*.yaml` is git-ignored; only the
> `*.yaml.example` templates are committed. Copy the template, fill in your own values, and
> never commit the result. Any new configuration YAML must follow the same rule: commit the
> `.example`, ignore the real file.

## First-time setup

```powershell
Copy-Item variables\core.yaml.example variables\core.yaml
Copy-Item variables\dev.yaml.example  variables\dev.yaml
```

Replace every `<REPLACE_WITH_...>` placeholder (at minimum `admin` / `adminObjectIds` and `baseName`).
`scripts/config.ps1` seeds a missing file from its `.example` automatically and then stops with
instructions, and it rejects unreplaced placeholders.

## Role-based access control actors

The `admin` and `user` variables configure role assignments for human actors or security groups:

- `admin`: Granted the highest level of permissions across data and control planes for all deployed services (Key Vault Administrator, Storage Blob Data Owner, OpenAI Contributor, AI Administrator, VM Administrator Login, Log Analytics Contributor, Resource Group Contributor & User Access Administrator).
- `user`: Granted permissions to use, operate, modify, and view across all services (Key Vault Secrets User & Officer, OpenAI User, Storage Blob Data Contributor, AI Developer, VM User Login, Log Analytics Reader, Resource Group Reader).

Both support arrays of objects (`- objectId: '...', principalType: 'User'|'Group'|'ServicePrincipal'`) or simple object ID strings. Leaving an array empty (`[]`) skips role assignments cleanly.

Configuration is merged in this order:

1. `core.yaml` shared defaults
2. `dev.yaml` or `uat.yaml` environment overrides
3. Subscription-derived name suffix calculated by the scripts

## Component deployment flags

Each environment file carries `deploy*` flags. `true` deploys the component and keeps it
current; `false` makes the next `scripts/deploy.ps1` run remove it if a previous run created it.

| Flag | Deploys | Removed when `false` |
|---|---|---|
| `deployStorage` | Storage account, blob container, blob private endpoint | Private endpoint, then the storage account |
| `deployLogAnalytics` | Log Analytics workspace and resource diagnostics | Diagnostic settings, then the workspace |
| `deployAiFoundry` | AI Hub, AI Project, hub private endpoint | Project, hub, then the hub private endpoint |
| `deployVm` | Jumpbox VM, NIC, public IP, NSG, OS disk, auto-shutdown schedule | Schedule, VM, **OS disk**, NIC, public IP, NSG |
| `deployAutomation` | Automation Account, its identity, repository runbooks | Automation Account and its managed identity |

Components without a flag are never removed because they hold deployment state or everything
else depends on them: resource groups, the virtual network and subnets, private DNS zones and
links, Key Vault and its private endpoint, Azure OpenAI and its private endpoint, and the
hub/VM managed identities.

Dependency rules enforced by `scripts/config.ps1`:

- `deployAiFoundry` requires `deployStorage`
- `enableAuditDiagnostics` requires `deployLogAnalytics`
- `deployAutomation` requires `deployVm`
- `vmStartScheduleEnabled` requires `deployAutomation`
- `vmAutoShutdownEnabled` requires `deployVm`

## Where values belong

All SKU, capacity, environment identity, service-connection selections, GitHub OIDC secret-name selections, and optional public IP DNS labels belong in the environment YAML. Shared networking, retention, API, image publisher/offer/version, Automation runtime/schedule, guest time zone, operational, and tag defaults belong in `core.yaml`. Every variable must retain an inline purpose and allowed-values comment. No other file in this repository may contain your configuration values — documentation and code refer to the variable name instead.

`vmPublicIpDnsNameLabel` configures the optional DNS label on the jumpbox VM public IP. Leave it empty (`''`) to deploy only the static public IP address, or set a region-unique label such as `az-swe-aifp` to produce an Azure DNS name like `az-swe-aifp.swedencentral.cloudapp.azure.com` when `location` is `swedencentral`.

GitHub Actions deployment and cleanup workflows read these environment YAML keys before `azure/login`:

| Variable | Default value | Purpose |
|---|---|---|
| `githubAzureClientIdSecretName` | `AZURE_CLIENT_ID` | Name of the GitHub secret containing the OIDC application/client ID |
| `githubAzureTenantIdSecretName` | `AZURE_TENANT_ID` | Name of the GitHub secret containing the Microsoft Entra tenant ID |
| `githubAzureSubscriptionIdSecretName` | `AZURE_SUBSCRIPTION_ID` | Name of the GitHub secret containing the Azure subscription ID |

Change the values, for example to `AZURE_CLIENT_ID_01`, `AZURE_TENANT_ID_01`, and `AZURE_SUBSCRIPTION_ID_01`, when an environment should use differently named GitHub secrets.

`scripts/config.ps1` is the authoritative parser and validator. Update it, its `.example` templates, Bicep parameters, tests, and documentation whenever a variable is added or renamed.

For tabular specifications of resources configured by these variables, see the [Architecture Documentation](../docs/README.md).

Update this README whenever a variable is added, renamed, or moved between `core.yaml` and an environment file; see [../.github/instructions/documentation-sync.instructions.md](../.github/instructions/documentation-sync.instructions.md).
