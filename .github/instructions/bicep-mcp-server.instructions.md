---
applyTo: "bicep/**/*.bicep,bicep/**/*.bicepparam,.mcp.json,.vscode/mcp.json"
---

# Bicep MCP server usage

This repository registers the official Bicep MCP server (`Azure.Bicep.McpServer`, run through `dnx`) in [`.mcp.json`](../../.mcp.json) (Agent Host and portable Copilot clients) and [`.vscode/mcp.json`](../../.vscode/mcp.json) (VS Code workspace UI). Use its tools instead of guessing at resource schemas, hand-formatting templates, or manually tracing module references.

## Match the Bicep work to the right tool

| Kind of Bicep work in this repo | Use this Bicep MCP tool |
|---|---|
| Adding a new Azure service/module (`bicep/modules/*.bicep` plus wiring into `bicep/templates/main.bicep`) | `list_az_resource_types_for_provider` to confirm the exact resource type name, then `get_az_resource_type_schema` for that type and API version before writing properties |
| Changing an existing resource's API version or properties | `get_az_resource_type_schema` to confirm the new schema/allowed values before editing; `get_bicep_file_diagnostics` after editing |
| Writing or reviewing any module for secure defaults | `get_bicep_best_practices` before/while writing, to stay aligned with this repo's private-endpoint, disabled-public-access, and RBAC conventions |
| Refactoring module wiring, outputs, or parameters in `main.bicep` | `get_file_references` to see the current module/parameter dependency graph before moving or renaming things |
| Formatting any `.bicep` file after edits | `format_bicep_file` instead of hand-formatting |
| Validating a `.bicep` file compiles cleanly, beyond `az bicep build`/`lint` | `get_bicep_file_diagnostics` |
| Deciding whether a new service should use a standard module instead of a hand-written one | `list_avm_metadata` to check for an applicable Azure Verified Module before hand-rolling a new `bicep/modules/*.bicep` file |
| Previewing the effect of a parameter/config change before running `-WhatIf` against Azure | `get_deployment_snapshot` against `bicep/templates/main.bicepparam` |
| Converting an externally sourced ARM JSON template or parameters file (for example an Azure docs quickstart or an exported ARM template) into this repo's Bicep style | `decompile_arm_template_file` / `decompile_arm_parameters_file`, then still apply the conventions in `bicep-service-change.instructions.md` (naming, tags, private endpoints) |

## How to invoke it

- The server is already registered for this workspace; no extra setup should be required. If the `bicep` MCP tools are unavailable, confirm `dnx` and a .NET 10+ SDK are on `PATH` before falling back to manual `az bicep` commands.
- Prefer the MCP tools over manual guesses for resource schemas, API versions, and formatting; they reduce the risk of inventing property names that do not exist for a given API version.
- The MCP tools do not deploy or execute the template and are not a substitute for validation. Still run `.\scripts\test.ps1 -Mode Static` and `.\scripts\scan.ps1`, and use `-WhatIf` for any change destined for a live environment.

## Keep this skill current

If a Bicep task needs steps beyond what is listed above (a new MCP tool, a new kind of Bicep work in this repo, or a workflow refinement you discovered while completing a task), update this file with what you learned before finishing the task.
