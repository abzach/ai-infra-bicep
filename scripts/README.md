# PowerShell automation

| Script | Purpose |
|---|---|
| `deploy.ps1` | Validate context, self-remediate missing role-assignment permission, apply component deployment flags, skip already-current environments, preview/deploy Bicep, publish runbooks through ARM, configure diagnostics, sync secrets through ARM, bootstrap the VM, and hand off local credentials |
| `cleanup.ps1` | Preview or delete only expected, tag-validated environment resource groups |
| `config.ps1` | Seed missing `variables/*.yaml` from their `.example`, then parse, merge, derive, and validate YAML configuration including deployment-flag dependencies |
| `common.ps1` | Shared output, retry, and resource helpers |
| `setup.ps1` | Install and configure the chat application inside the VM |
| `test.ps1` | Static, deployed-resource, smoke, and dual-model tests |
| `security-scan.ps1` | Validate generated template security invariants |
| `scan-ai-safety.ps1` | Scan markdown and instruction files for AI safety, prompt injections, jailbreaks, hidden unicode smuggling, and harmful instructions |

Use PowerShell 7+. `deploy.ps1` installs or upgrades the Azure CLI-managed Bicep binary to the latest available release without prompting before continuing. Top-level scripts under `automation/` are parsed, hashed, provisioned, uploaded, and published as Automation runbooks; schedule links are created only after publication, and what-if mode performs validation and preview only. Normal reruns exit early when all expected resources and runbook schedule links exist and the recorded `desiredStateHash` matches the local desired state; use `-ForceRedeploy` to bypass this guard. Local successful deployments place a plaintext credential handoff under ignored `.local/credentials/`; move the password to a password manager, delete the file, and rotate the VM password. CI never prints or writes that credential.

## Local troubleshooting logs (`.logs/`)

`deploy.ps1`, `cleanup.ps1`, and `test.ps1` dot-source `common.ps1`, which mirrors every `Write-Task`/`Write-Exists`/`Write-Needed`/`Write-Info` console message into a git-ignored `.logs/ai-infra.log` file at the repo root (see the root-level `.gitignore` `.logs/` entry). Only those already-curated messages are persisted — never raw Azure CLI/API output — so the file stays small and never contains secrets by construction; as defense-in-depth, `common.ps1` also redacts any password/secret/token/key/bearer-token/SAS-signature-shaped substring before writing a line. The log rolls over at 5 MB: the active file is renamed to `ai-infra.log.old` (overwriting any previous one) and a fresh `ai-infra.log` is started, so at most two files (current + old) ever exist. `.logs/` is local-only and must never be committed.

At script completion, `common.ps1` prints an execution timing summary table and writes the same table to `.logs/ai-infra.log` with `TIME` entries. The summary includes every `Write-Task` operation classified as a stage, step, or resource operation, plus a final total duration row, so deployment and cleanup performance can be tuned over time. Existing traps also emit the timing summary before failed scripts exit.

## `deploy.ps1` behavior worth knowing

- **Role-assignment preflight.** If the deploying identity has neither `Owner` nor `User Access Administrator` at subscription scope, the script attempts to grant itself `User Access Administrator`, then (interactive users only) attempts Entra `elevateAccess` and retries, re-verifies with backoff, and only then fails with the exact remediation to request. `-SkipRoleElevation` skips the elevation attempt; CI runs skip it automatically.
- **Component deployment flags.** `deployStorage`, `deployLogAnalytics`, `deployAiFoundry`, `deployVm`, and `deployAutomation` from the environment YAML are passed to Bicep and drive a pre-deploy removal pass for components whose flag is `false`, including the jumpbox OS disk. Key Vault, networking, private DNS, Azure OpenAI, their private endpoints, and the managed identities are never removed. The no-op guard also fails a disabled component that still exists, so flipping a flag always triggers a deployment run.
- **Public IP DNS label.** `vmPublicIpDnsNameLabel` from the environment YAML is passed to Bicep for the VM public IP. Empty means no public DNS label; a value such as `az-swe-aifp` creates `<label>.<location>.cloudapp.azure.com`.
- **VM password preservation.** A rerun never changes a password the VM already has. A new password is generated only on first deploy, when the VM is being recreated (Spot/Regular priority change), or when `-RotateVmPassword` is passed. Otherwise the Key Vault sync and `az vm user update` are skipped, and the previously issued password remains valid.
- **Stale role-assignment cleanup.** Before deploying, the script removes managed-identity data-plane assignments and any admin/user actor assignment for a template-managed role at (or below) the environment resource groups. Azure rejects a second assignment of the same role/principal/scope under a different deterministic name with `RoleAssignmentExists`, so the templates recreate these assignments under the names `bicep/modules/actorroles.bicep` and `bicep/modules/networkroles.bicep` own. Assignments inherited from subscription or management-group scope are never touched.

Detailed architecture and resource documentation is available in the [Architecture Documentation](../docs/README.md).

Update this README whenever a script's behavior, parameters, or exit conditions change; see [../.github/instructions/documentation-sync.instructions.md](../.github/instructions/documentation-sync.instructions.md).
