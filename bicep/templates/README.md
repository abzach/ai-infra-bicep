# Bicep templates

- `main.bicep` is the subscription-scope orchestration template.
- `main.bicepparam` documents all template parameters and safe example values, including Automation runtime, runbook descriptors, and VM-start scheduling.

Normal deployments should use `scripts/deploy.ps1`, which merges YAML configuration, derives names, supplies the secure VM password, and invokes the template. Do not place real passwords or tenant-specific secrets in `main.bicepparam`.

Detailed resource documentation and configuration tables can be found in the [Architecture Documentation](../../docs/README.md).

This README must be updated whenever `main.bicep` or `main.bicepparam` parameters change; see [../../.github/instructions/documentation-sync.instructions.md](../../.github/instructions/documentation-sync.instructions.md).
