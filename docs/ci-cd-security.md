# CI/CD & Public Repository Security

This document details the security posture, risks, and mitigations when managing GitHub Actions workflows and Azure DevOps pipelines in a public repository.

## Overview & Threat Model

Hosting Infrastructure as Code (IaC) and workflow files in a public GitHub repository provides open visibility into automation definitions, Bicep templates, and deployment scripts. While workflow files themselves are public, **unauthorized users cannot trigger manual workflows, access secrets, or execute actions against your Azure subscription** without explicit write permissions.

| Threat | Risk Level | Mitigation in Repository |
|---|---|---|
| **Public Source Exposure** | Low | No credentials, tenant IDs, subscription IDs, or passwords are committed to source files. All secrets are passed via environment variables or secret vaults. |
| **Unauthorized Workflow Execution** | Medium | Workflows use `workflow_dispatch` only (no automatic triggers on untrusted pull requests or commits). Only repository collaborators with write access can trigger runs. |
| **Secret Exfiltration in Logs** | High | Scripts and pipelines suppress secret echoing, omit sensitive parameters from verbose output, store local VM credentials in `.local/` (git-ignored), and write only curated, secret-redacted troubleshooting messages to a size-capped, git-ignored `.logs/` folder (see `scripts/README.md`). |
| **Stolen Static Credentials** | Critical | Workflows use **OpenID Connect (OIDC)** federated credentials rather than long-lived client secrets or certificates. |
| **Accidental or Malicious Resource Deletion** | Critical | Cleanup workflows require explicit environment selection, execute a `-WhatIf` preview stage first, and can be gated with environment approvals. |
| **Broad Azure Permissions** | High | Workflows use least-privilege service principals scoped specifically to target resource groups or required subscription role assignments. |

## OpenID Connect (OIDC) Authentication

GitHub Actions connects to Azure using federated OpenID Connect tokens via the `azure/login@v3` action, eliminating static service principal secrets.

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - name: Resolve Azure login secret names
    id: azure-login-secrets
    shell: pwsh
    env:
      AI_INFRA_ENV_YAML: ${{ secrets.AI_INFRA_ENV_YAML }}
    run: |
      # Reads githubAzure*SecretName values from variables/<environment>.yaml content.
  - name: Azure Login
    uses: azure/login@v3
    with:
      client-id: ${{ secrets[steps.azure-login-secrets.outputs.clientIdSecretName] }}
      tenant-id: ${{ secrets[steps.azure-login-secrets.outputs.tenantIdSecretName] }}
      subscription-id: ${{ secrets[steps.azure-login-secrets.outputs.subscriptionIdSecretName] }}
```

### OIDC Best Practices
1. **Strict Subject Identifier (Subject Claim):** Configure Azure App Registration federated credentials with an exact subject condition matching the repository, environment, or branch:
   - Specific Environment: `repo:abzach/ai-infra-bicep:environment:dev`
   - Specific Branch: `repo:abzach/ai-infra-bicep:ref:refs/heads/main`
2. **Avoid Wildcard Subjects:** Never configure federated credentials with `repo:abzach/ai-infra-bicep:*` or branch wildcards without environment protection.

## GitHub Secrets and Environments

Configure the following secrets in GitHub repository or environment settings:

| Secret Name | Description | Recommended Scope |
|---|---|---|
| Value of `githubAzureClientIdSecretName` in `variables/<environment>.yaml` (default `AZURE_CLIENT_ID`) | Application (client) ID of the Azure AD App Registration | Repository or Environment |
| Value of `githubAzureTenantIdSecretName` in `variables/<environment>.yaml` (default `AZURE_TENANT_ID`) | Microsoft Entra ID Tenant ID | Repository or Environment |
| Value of `githubAzureSubscriptionIdSecretName` in `variables/<environment>.yaml` (default `AZURE_SUBSCRIPTION_ID`) | Target Azure Subscription ID | Repository or Environment |
| `VM_ADMIN_PASSWORD` | Secure password for the Jumpbox Windows VM local administrator | Environment (`dev` / `uat`) |

### GitHub Environments & Protection Rules
- **Environment Gating:** Create `dev` and `uat` environments in GitHub repository settings.
- **Required Reviewers:** Configure required approvals for deployment and cleanup environments (especially for destructive actions like `cleanup.yml`).
- **Deployment Branches:** Restrict deployment execution to protected branches such as `main`.

## Destructive Cleanup Safeguards

The cleanup workflow (`.github/workflows/cleanup.yml` and `pipelines/cleanup.yml`) provides a guarded two-stage deletion model:

1. **Stage 1: Preview (`-WhatIf`):** Evaluates environment resource groups (`rg-<baseName>-core-<env>-<suffix>` and `rg-<baseName>-network-<env>-<suffix>`) and prints exact resource deletion candidates without mutating Azure state.
2. **Stage 2: Destroy (`-Force`):** Deletes only tag-validated resource groups containing matching `workload=enterprise-ai-foundry` and `environment=<env>` tags.

## Pipeline Supply Chain Security

- **Pinning Action Versions:** Regularly audit workflow dependencies and consider pinning GitHub Actions to exact full-length commit SHAs.
- **Workflow Permissions:** Enforce minimum workflow permissions (`id-token: write`, `contents: read`).
- **Azure DevOps Service Connections:** Limit the Azure Resource Manager service connection scope to dedicated management groups or subscriptions.

## Related Documentation

- [GitHub Actions Workflows Documentation](github-actions.md)
- [Azure DevOps Pipelines Documentation](azure-pipelines.md)
- [Role-Based Access Control Documentation](role-based-access-control.md)
- [Documentation Index](index.md)
