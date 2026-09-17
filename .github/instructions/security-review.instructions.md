---
applyTo: "**/*.bicep,scripts/**/*.ps1,app/**/*.py,.github/workflows/**/*.yml,pipelines/**/*.yml,variables/**/*.yaml"
---

# Security hardening and review

- Treat public network access on Key Vault, Storage, Azure OpenAI, AI Hub, and AI Project as a high-severity regression.
- Preserve Storage HTTPS-only, TLS 1.2+, no blob public access, no shared-key access, and network ACL default deny.
- Preserve Key Vault RBAC authorization, empty access policies, private endpoint access, and ARM-based secret resource writes.
- Preserve Azure OpenAI local-auth disablement and model access through Entra ID.
- Keep VM Trusted Launch, Secure Boot, vTPM, Windows client licensing, antimalware, Azure Monitor Agent, and disk encryption.
- Keep RDP source CIDRs explicit and retain the deny-all RDP rule.
- Ensure new scripts and workflows never echo passwords, tokens, tenant-specific secrets, or generated credential files.
- Run `scripts/safety.ps1` to detect prompt injections, jailbreaks, hidden unicode smuggling, and harmful AI instructions in documentation and prompt files.
- Support `admin` and `user` actor RBAC assignments with graceful empty fallbacks across both data and control planes.
- Update `scripts/scan.ps1` and docs for every new invariant that future reviews should enforce.
- When scanning compiled ARM, support both resource arrays and language-version 2 symbolic-name resource objects, including resources inside conditional nested deployments.
- Use the Bicep MCP server's `get_bicep_best_practices` and `get_bicep_file_diagnostics` tools when reviewing `.bicep` files for security regressions; see `bicep-mcp-server.instructions.md`.
- Update every doc affected by a security-relevant change in the same change; see `documentation-sync.instructions.md`.

## Keep this skill current

If this review needed steps beyond what is listed above, add them to this file before finishing so future security reviews benefit.
