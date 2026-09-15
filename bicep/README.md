# Bicep infrastructure

Standalone Bicep for the subscription-scope Azure AI Foundry deployment.

- `templates/main.bicep` creates environment resource groups and orchestrates modules.
- `modules/` contains network, identity, security, observability, AI, Storage, Key Vault, and VM resources.
- `templates/main.bicepparam` is a documented example parameter file; `deploy.ps1` generates the effective secure parameter JSON at runtime.

Build and lint all templates with:

```powershell
.\scripts\test.ps1 -Mode Static
```

Do not commit generated JSON output or parameter files containing secrets.
