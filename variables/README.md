# Environment configuration

Configuration is merged in this order:

1. `core.yaml` shared defaults
2. `dev.yaml` or `uat.yaml` environment overrides
3. Subscription-derived name suffix calculated by the scripts

All SKU, capacity, environment identity, and service-connection selections belong in the environment YAML. Shared networking, retention, API, image publisher/offer/version, operational, and tag defaults belong in `core.yaml`. Every variable must retain an inline purpose and allowed-values comment.

`scripts/config.ps1` is the authoritative parser and validator. Update it, Bicep parameters, tests, and documentation whenever a variable is added or renamed.

Update this README whenever a variable is added, renamed, or moved between `core.yaml` and an environment file; see [../.github/instructions/documentation-sync.instructions.md](../.github/instructions/documentation-sync.instructions.md).
