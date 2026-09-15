---
applyTo: "bicep/**/*.bicep,variables/**/*.yaml"
---

# Bicep service and module changes

- Keep `bicep/templates/main.bicep` as the subscription-scope entry point and place resource-specific logic in `bicep/modules/`.
- Use deterministic names from `scripts/config.ps1` and `main.bicep`; do not invent one-off resource names.
- Apply the shared `tags` object to every taggable resource so `createdDate`, `lastModifiedDate`, and `desiredStateHash` remain consistent.
- Keep public network access disabled for Key Vault, Storage, Azure OpenAI, AI Hub, and AI Project unless a task explicitly changes the security model.
- Prefer private endpoints and private DNS zone links for new data-plane services.
- Add outputs only when a deployment script, test, module, or documentation needs them.
- Put shared non-SKU defaults in `variables/core.yaml`; put SKU, capacity, identity, and environment-specific values in `variables/dev.yaml` or `variables/uat.yaml`.
- Update `scripts/security-scan.ps1` when adding resources with security invariants that must not regress.

