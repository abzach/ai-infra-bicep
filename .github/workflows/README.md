# GitHub workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `deploy-dev.yml` | Manual | Preview, deploy, and validate the development environment |
| `cleanup-dev.yml` | Manual | Preview and delete tag-validated development resource groups |

Both workflows authenticate with GitHub OIDC. Cleanup is destructive after its preview job and should be protected with GitHub environments or equivalent approval controls.
