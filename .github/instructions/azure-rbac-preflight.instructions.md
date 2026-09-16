---
applyTo: "scripts/deploy.ps1,scripts/common.ps1,.github/workflows/**/*.yml,pipelines/**/*.yml"
---

# Azure RBAC preflight and self-elevation

`bicep/templates/main.bicep` creates Azure RBAC role assignments (Storage Blob Data Contributor, Key Vault Secrets User, Key Vault Secrets Officer, Cognitive Services OpenAI User). A deploying identity therefore needs `Microsoft.Authorization/roleAssignments/write` at subscription scope — normally through **Owner** or **User Access Administrator**.

The first run of `scripts/deploy.ps1` used to fail here for a freshly logged-in user. `deploy.ps1` now performs an automatic preflight, implemented by `Initialize-RoleAssignmentWritePermission` in [`scripts/common.ps1`](../../scripts/common.ps1).

## What the script does, in order

1. **Detect.** Resolve the deploying object ID (`az ad signed-in-user show` for users, `az ad sp show` for service principals) and list role assignments at subscription scope **including inherited** management-group/root assignments.
2. **Short-circuit.** If `Owner` or `User Access Administrator` is already effective, log it and continue. This keeps normal reruns a no-op.
3. **Self-grant.** Attempt `az role assignment create --role "User Access Administrator" --scope /subscriptions/<id>` for the deploying identity. This succeeds when the identity already holds role-assignment write higher up (for example Owner at a management group) but not at the subscription itself.
4. **Elevate (interactive users only).** If the self-grant fails, call the Entra `elevateAccess` API (`POST https://management.azure.com/providers/Microsoft.Authorization/elevateAccess?api-version=2016-07-01`). This succeeds only for an Entra **Global Administrator** who has "Access management for Azure resources" available, and grants User Access Administrator at root (`/`) scope for a limited period. The script then retries step 3 so the permission is pinned at subscription scope.
5. **Re-verify.** Re-read the effective assignments with backoff, because Azure RBAC propagation is eventually consistent.
6. **Fail loudly.** Only if all of the above fail does the script stop, printing the exact one-line `az role assignment create` command an administrator must run, plus the portal path.

## Rules for agents and contributors

- **Never skip the preflight to "get the deployment moving".** A missing role surfaces much later as an opaque `AuthorizationFailed` inside a nested module deployment.
- **Never widen the grant.** Grant `User Access Administrator` at subscription scope only. Do not grant `Owner`, and do not grant at root or management-group scope from the script.
- **Never attempt elevation in CI.** Service principals cannot use `elevateAccess`. When `$isCi` is true, or when `-SkipRoleElevation` is supplied, the script reports the required grant and fails instead of mutating tenant-level access. Pipeline identities must be granted the role once, out of band, by an administrator.
- **Keep it idempotent.** Every step is skipped when the permission is already effective, so `deploy.ps1` reruns must not create duplicate assignments or re-elevate.
- **Do not print identity secrets.** Object IDs are already logged for troubleshooting; do not add tenant secrets, tokens, or credentials to the output, and never persist them to tracked files.

## Investigating a failure

Use the Azure MCP server (see [`azure-mcp-server.instructions.md`](azure-mcp-server.instructions.md)) to read the deploying principal's effective role assignments and the failed deployment operation, rather than guessing. Then fix the repository source, not the live environment, unless the fix genuinely is a one-time role grant.

## Related

- [`deployment-orchestration.instructions.md`](deployment-orchestration.instructions.md) — ordering rules for `deploy.ps1`.
- [`security-review.instructions.md`](security-review.instructions.md) — least-privilege invariants that this preflight must not weaken.

## Keep this skill current

If the preflight needs a new step, a new failure mode, or a new escape hatch, update this file with what you learned before finishing the task.
