---
applyTo: ".github/workflows/**/*.yml,pipelines/**/*.yml,variables/**/*.yaml"
---

# Pipeline and workflow changes

- Keep GitHub Actions and Azure DevOps pipelines aligned: static/security gate, what-if planning, deploy, then validation.
- Use GitHub OIDC for Actions and the configured Azure DevOps service connection for pipelines.
- Pass VM passwords only through protected secrets or secret variables; never print them or write credential files in CI.
- Keep deployment commands non-interactive and explicit about `-EnvironmentSuffix`.
- Development deploy reruns should naturally hit the `deploy.ps1` no-op path when the deployed desired-state hash is current.
- Update `.github/README.md`, `.github/workflows/README.md`, `pipelines/README.md`, and indexes when workflow inventory or behavior changes; see `documentation-sync.instructions.md`.

## Keep this skill current

If this task needed steps beyond what is listed above, add them to this file before finishing so future pipeline/workflow changes benefit.

