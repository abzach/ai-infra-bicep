# Bicep templates

- `main.bicep` is the subscription-scope orchestration template.
- `main.bicepparam` documents all template parameters and safe example values.

Normal deployments should use `scripts/deploy.ps1`, which merges YAML configuration, derives names, supplies the secure VM password, and invokes the template. Do not place real passwords or tenant-specific secrets in `main.bicepparam`.
