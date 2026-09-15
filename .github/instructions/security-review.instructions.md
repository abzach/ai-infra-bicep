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
- Update `scripts/security-scan.ps1` and docs for every new invariant that future reviews should enforce.

