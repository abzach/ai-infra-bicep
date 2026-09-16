---
applyTo: "**/*.bicep,**/*.bicepparam,scripts/**/*.ps1,variables/**/*.yaml,.mcp.json,.vscode/mcp.json"
---

# Azure MCP server usage

This repository registers the official Azure MCP server (`@azure/mcp`, run through `npx`) in [`.mcp.json`](../../.mcp.json) and [`.vscode/mcp.json`](../../.vscode/mcp.json), alongside the Bicep MCP server. The Azure MCP server acts on the **live subscription that the local `az login` session is already connected to**, so an agent can investigate a real environment instead of guessing.

Use it whenever a task depends on what is actually deployed, what a region/subscription actually supports, or why a deployment actually failed.

## Division of labour: Azure MCP vs Bicep MCP

| Question | Server |
|---|---|
| "What properties/API versions exist for this resource type?" | Bicep MCP (`get_az_resource_type_schema`, `list_az_resource_types_for_provider`) |
| "Does this template compile, lint, and format cleanly?" | Bicep MCP (`get_bicep_file_diagnostics`, `format_bicep_file`) |
| "What is deployed right now, and in what state?" | Azure MCP (resource/group queries, Resource Graph) |
| "Why did `deploy.ps1` fail?" | Azure MCP (deployment operations, activity log, resource errors) |
| "Is this SKU / model / capacity available in this region and subscription?" | Azure MCP (quota, SKU, Cognitive Services model catalogue) |
| "Does the deploying identity actually hold the roles the template needs?" | Azure MCP (role assignment queries) |
| "Is the private endpoint / DNS record actually resolving?" | Azure MCP (network resource inspection) |

The two are complementary: **Azure MCP tells you the truth about the tenant; Bicep MCP tells you the truth about the schema.** Confirm the live constraint first, then confirm the schema, then change the code.

## Repository use cases

Use the Azure MCP server for the following recurring tasks in this codebase. In every case, finish by fixing the repository source (Bicep module, `scripts/*.ps1`, or `variables/*.yaml`) — never by making an out-of-band portal or CLI change that the next `deploy.ps1` run would revert.

### 1. Diagnosing a failed `scripts/deploy.ps1` run

1. Read the failed subscription deployment and its failed operations to get the real `code`/`message`, not just the script's summary.
2. Inspect the target resource group and the specific resource that failed.
3. Check the activity log for policy denials (`RequestDisallowedByPolicy`) — this subscription enforces disabled public network access.
4. Map the root cause back to the owning module in `bicep/modules/` and fix it there.

### 2. Capacity, SKU, quota, and region validation

Before changing `vmSize`, `skuName`, `modelSkuName`, `capacityK`, `secondaryCapacityK`, `location`, or model name/version in `variables/*.yaml`:

1. Confirm the VM SKU exists, is not restricted, and supports the features the template requires (accelerated networking, Trusted Launch, Spot when `vmUseSpot: true`).
2. Confirm the Azure OpenAI model name/version/SKU is offered in `location` for this subscription, and that the requested TPM fits remaining quota.
3. Only then update the YAML and re-run `-WhatIf`.

### 3. RBAC and identity troubleshooting

1. Resolve the signed-in principal's object ID and its subscription-scope role assignments.
2. Verify the managed identities hold exactly the resource-scoped roles the repo requires (`Key Vault Secrets User`, `Cognitive Services OpenAI User`, and Storage Blob Data Contributor for the hub identity).
3. See [`azure-rbac-preflight.instructions.md`](azure-rbac-preflight.instructions.md) for the role-assignment-write preflight that `deploy.ps1` performs automatically.

### 4. Private networking verification

1. Inspect private endpoints, their connection state, and the private DNS zones plus VNet links in the network resource group.
2. Confirm Key Vault / Storage / Azure OpenAI still report `publicNetworkAccess: Disabled`.
3. Remember that the deployment host has no data-plane access by design: use the jumpbox or ARM-plane calls, and never "fix" a failure by re-enabling public access.

### 5. Drift and flag verification

After toggling a `deploy*` flag in `variables/<env>.yaml` (see [`bicep-service-change.instructions.md`](bicep-service-change.instructions.md)), use Azure MCP to confirm that disabled components are genuinely gone and that protected components (Key Vault, network, Azure OpenAI, managed identities) are untouched.

### 6. Cost and hygiene checks

Inspect the VM power state, auto-shutdown schedule, Automation schedules, and Log Analytics daily cap when a cost question comes up, instead of assuming the YAML defaults are in effect.

## Rules

- The Azure MCP server inherits the local `az login` context. Always confirm the active subscription before acting on results.
- Treat Azure MCP as **read-first**. Prefer read/list/query operations for investigation. Do not use it to create, mutate, or delete environment resources that `deploy.ps1` owns; that is the deployment script's job and an out-of-band change breaks the `desiredStateHash` no-op guard.
- Never echo secrets, credentials, connection strings, tenant IDs, subscription IDs, or object IDs retrieved through Azure MCP into tracked files, documentation, or commit messages.
- MCP findings are evidence, not validation. Still run `.\scripts\test.ps1 -Mode Static`, `.\scripts\security-scan.ps1`, and `.\scripts\deploy.ps1 -EnvironmentSuffix <env> -WhatIf`.
- If the `azure` MCP tools are unavailable, confirm Node.js 20+ and `npx` are on `PATH`, then fall back to `az` CLI commands in the terminal.

## Keep this skill current

If an investigation needs steps beyond what is listed above, update this file with what you learned before finishing the task.
