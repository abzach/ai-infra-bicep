# GitHub workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `deploy-dev.yml` | Manual | Preview, deploy, and validate the development environment |
| `cleanup-dev.yml` | Manual | Preview and delete tag-validated development resource groups |

Both workflows authenticate with GitHub OIDC. Cleanup is destructive after its preview job and should be protected with GitHub environments or equivalent approval controls.

Update this README whenever a workflow is added or its triggers/stages change; see [../instructions/documentation-sync.instructions.md](../instructions/documentation-sync.instructions.md).
