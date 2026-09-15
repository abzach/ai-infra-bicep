# PowerShell automation

| Script | Purpose |
|---|---|
| `deploy.ps1` | Validate context, skip already-current environments, preview/deploy Bicep, configure diagnostics, sync secrets through ARM, bootstrap the VM, and hand off local credentials |
| `cleanup.ps1` | Preview or delete only expected, tag-validated environment resource groups |
| `config.ps1` | Parse, merge, derive, and validate YAML configuration |
| `common.ps1` | Shared output, retry, and resource helpers |
| `setup.ps1` | Install and configure the chat application inside the VM |
| `test.ps1` | Static, deployed-resource, smoke, and dual-model tests |
| `security-scan.ps1` | Validate generated template security invariants |

Use PowerShell 7+. Normal reruns exit early when all expected resources exist and the recorded `desiredStateHash` matches the local desired state; use `-ForceRedeploy` to bypass this guard. Local successful deployments place a plaintext credential handoff under ignored `.local/credentials/`; move the password to a password manager, delete the file, and rotate the VM password. CI never prints or writes that credential.
