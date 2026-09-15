# GitHub workflows

Consolidated workflows with runtime environment choice (`dev` or `uat`):

| Workflow | Trigger | Inputs | Purpose |
|---|---|---|---|
| `deploy.yml` | `workflow_dispatch` (Manual) | `environment: [dev, uat]` | Preview (What-If), deploy Bicep infrastructure, and validate the environment |
| `cleanup.yml` | `workflow_dispatch` (Manual) | `environment: [dev, uat]` | Preview (What-If) and delete tag-validated resource groups |

Both workflows authenticate with GitHub OIDC. Cleanup is destructive after its preview job and should be protected with GitHub environments or equivalent approval controls.

For detailed threat modeling and workflow architecture, see:
- [GitHub Actions Workflows Documentation](../../docs/github-actions.md)
- [CI/CD & Public Repository Security Documentation](../../docs/ci-cd-security.md)

Update this README whenever a workflow is added or its triggers/stages change; see [../instructions/documentation-sync.instructions.md](../instructions/documentation-sync.instructions.md).
