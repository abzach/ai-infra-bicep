---
applyTo: "variables/**,scripts/**/*.ps1,bicep/**/*.bicep,bicep/**/*.bicepparam,docs/**/*.md,README.md,index.md,.github/workflows/**/*.yml,pipelines/**/*.yml"
---

# Local configuration files

User-specific configuration lives only in `variables/*.yaml`, and those files are never committed.
Only `variables/*.yaml.example` templates are tracked.

## Rules

1. **Never commit a real configuration file.** `.gitignore` contains `variables/*.yaml` with a
   `!variables/*.yaml.example` exception. Do not weaken or override that rule, and never use
   `git add -f` on a `variables/*.yaml` file.
2. **Every new configuration YAML needs an example.** If you introduce a new kind of YAML
   configuration (a new environment, a new layer, or a new folder), commit only its
   `<name>.yaml.example` template and confirm the real file is ignored.
3. **Examples carry placeholders, not values.** Anything that identifies a person, tenant,
   subscription, region choice, naming prefix, or service connection must appear as
   `<REPLACE_WITH_...>` or a neutral, obviously generic default (`eastus`, `UTC`, `Etc/UTC`).
   Never copy a working environment's object IDs, prefixes, regions, SKUs, or time zones into
   a tracked file.
4. **No configuration values anywhere else.** Bicep parameter defaults, `main.bicepparam`,
   scripts, tests, workflows, pipelines, `README.md`, `index.md`, and `docs/*.md` must describe
   *which* variable controls a behavior, not the value a particular user chose. Write
   "`vmSize` from your environment YAML", not the concrete SKU.
5. **Wire new settings end to end.** A new value goes into `variables/core.yaml` (shared,
   non-SKU defaults) or `variables/<env>.yaml` (identity, naming, SKU, capacity), plus the
   matching `.example`, then `scripts/config.ps1` validation, `scripts/deploy.ps1`,
   `bicep/templates/main.bicep`, affected modules, tests, and docs.
6. **Every variable keeps an inline comment** describing its purpose and allowed values.
7. **Bootstrap is automatic.** `scripts/config.ps1` seeds a missing `variables/<name>.yaml`
   from its `.example` and then stops with instructions. Keep that behavior and keep the
   placeholder validation (for example, the `adminObjectIds` GUID check) working.

## Checks before finishing

```powershell
git --no-pager status --short -- variables   # only *.yaml.example may be staged
git grep -n -I -E "<your prefix>|<your region>|<your object id>" -- . ":(exclude)variables/*.example"
.\scripts\test.ps1 -Mode Static
```

## Keep this skill current

If a task reveals another place where user configuration leaked into tracked files, or a new
configuration layer is added, update this file with the new rule before finishing the task.

## CI configuration path

CI never has a local `variables/*.yaml`. Workflows and pipelines supply the full file contents
through `AI_INFRA_CORE_YAML` and `AI_INFRA_ENV_YAML` (GitHub secrets, or the `aiInfraCoreYaml` /
`aiInfraEnvYaml` variables of the `ai-infra-<env>` Azure DevOps variable group).
`scripts/config.ps1` writes them to `variables/` for that run only. When you add a script that
loads configuration in CI, pass those two environment variables to it.
