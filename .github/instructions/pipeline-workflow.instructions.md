---
applyTo: ".github/workflows/**/*.yml,pipelines/**/*.yml,variables/**/*.yaml"
---

# Pipeline and workflow changes

- Keep GitHub Actions and Azure DevOps pipelines aligned: static/security gate, what-if planning, deploy, then validation.
- Consolidate deploy workflows into a single `deploy.yml` and cleanup workflows into a single `cleanup.yml` supporting runtime environment selection (`dev`/`uat`) rather than maintaining separate files per environment.
- Use GitHub OIDC for Actions and the configured Azure DevOps service connection for pipelines.
- Pass VM passwords only through protected secrets or secret variables; never print them or write credential files in CI.
- Keep deployment commands non-interactive and explicit about `-EnvironmentSuffix`.
- Development deploy reruns should naturally hit the `deploy.ps1` no-op path when the deployed desired-state hash is current.
- Update `.github/README.md`, `.github/workflows/README.md`, `pipelines/README.md`, `docs/`, and indexes when workflow inventory or behavior changes; see `documentation-sync.instructions.md`.


## Keep this skill current

If this task needed steps beyond what is listed above, add them to this file before finishing so future pipeline/workflow changes benefit.

## Configuration in CI

`variables/*.yaml` is untracked, so every CI step that loads configuration must receive
`AI_INFRA_CORE_YAML` and `AI_INFRA_ENV_YAML`:

- GitHub Actions: `env:` entries reading `secrets.AI_INFRA_CORE_YAML` and `secrets.AI_INFRA_ENV_YAML`.
- Azure DevOps: task-level `env:` entries reading `$(aiInfraCoreYaml)` and `$(aiInfraEnvYaml)` from the `ai-infra-<environment>` variable group, which also provides `serviceConnection` and `vmAdminPassword`.

Never reintroduce `- template: ../variables/<env>.yaml`; that file no longer exists in the repository.
