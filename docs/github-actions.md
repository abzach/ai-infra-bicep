# GitHub Actions Workflows

This document details the consolidated GitHub Actions workflows for deployment and cleanup in `.github/workflows/`.

## Consolidated Architecture

The repository provides three GitHub Actions workflows:

1. **Continuous Integration Tests (`.github/workflows/ci.yml`):** Automatically triggered on `push` to `main`, `pull_request` against `main`, or manual dispatch. Executes free automated static checks, Bicep build and lint, Automation runbook AST validation, IaC security policy scans, AI safety and prompt injection scans on markdown/instruction files, and Python application syntax checks without requiring cloud credentials.
2. **Deploy Workflow (`.github/workflows/deploy.yml`):** Runs What-If planning, deploys Bicep infrastructure, configures Key Vault secrets, bootstraps the Jumpbox VM, and executes post-deployment validation tests.
3. **Cleanup Workflow (`.github/workflows/cleanup.yml`):** Runs What-If resource group deletion preview and performs guarded environment cleanup.

## Workflow Overview

| Workflow File | Trigger | Runtime Inputs | Stages / Jobs | Description |
|---|---|---|---|---|
| `.github/workflows/ci.yml` | `push` (to `main`), `pull_request` (to `main`), `workflow_dispatch` | None | `static-tests`, `security-scan`, `ai-safety-scan`, `python-app-check`, `formatting-check` | Automated free CI test suite and AI safety scanner |
| `.github/workflows/deploy.yml` | `workflow_dispatch` (Manual) | `environment: [dev, uat]` | `planning` ➔ `deploy` ➔ `validate` | Multi-stage deployment orchestrator |
| `.github/workflows/cleanup.yml` | `workflow_dispatch` (Manual) | `environment: [dev, uat]` | `preview` ➔ `destroy` | Two-stage preview and deletion orchestrator |

## Deploy Workflow (`deploy.yml`) Specification

```yaml
name: Deploy

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        default: 'dev'
        type: choice
        options:
          - dev
          - uat

permissions:
  id-token: write
  contents: read

jobs:
  planning:
    name: Planning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Resolve Azure login secret names
        id: azure-login-secrets
        shell: pwsh
        env:
          AI_INFRA_ENV_YAML: ${{ secrets.AI_INFRA_ENV_YAML }}
        run: |
          # Reads githubAzure*SecretName values from variables/<environment>.yaml content.
      - uses: azure/login@v3
        with:
          client-id: ${{ secrets[steps.azure-login-secrets.outputs.clientIdSecretName] }}
          tenant-id: ${{ secrets[steps.azure-login-secrets.outputs.tenantIdSecretName] }}
          subscription-id: ${{ secrets[steps.azure-login-secrets.outputs.subscriptionIdSecretName] }}
      - shell: pwsh
        run: ./scripts/deploy.ps1 -EnvironmentSuffix ${{ inputs.environment }} -WhatIf

  deploy:
    name: Deploy
    needs: planning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Resolve Azure login secret names
        id: azure-login-secrets
        shell: pwsh
        env:
          AI_INFRA_ENV_YAML: ${{ secrets.AI_INFRA_ENV_YAML }}
        run: |
          # Reads githubAzure*SecretName values from variables/<environment>.yaml content.
      - uses: azure/login@v3
        with:
          client-id: ${{ secrets[steps.azure-login-secrets.outputs.clientIdSecretName] }}
          tenant-id: ${{ secrets[steps.azure-login-secrets.outputs.tenantIdSecretName] }}
          subscription-id: ${{ secrets[steps.azure-login-secrets.outputs.subscriptionIdSecretName] }}
      - shell: pwsh
        env:
          VM_ADMIN_PASSWORD: ${{ secrets.VM_ADMIN_PASSWORD }}
        run: ./scripts/deploy.ps1 -EnvironmentSuffix ${{ inputs.environment }} -VmAdminPassword $env:VM_ADMIN_PASSWORD

  validate:
    name: Validate
    needs: deploy
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Resolve Azure login secret names
        id: azure-login-secrets
        shell: pwsh
        env:
          AI_INFRA_ENV_YAML: ${{ secrets.AI_INFRA_ENV_YAML }}
        run: |
          # Reads githubAzure*SecretName values from variables/<environment>.yaml content.
      - uses: azure/login@v3
        with:
          client-id: ${{ secrets[steps.azure-login-secrets.outputs.clientIdSecretName] }}
          tenant-id: ${{ secrets[steps.azure-login-secrets.outputs.tenantIdSecretName] }}
          subscription-id: ${{ secrets[steps.azure-login-secrets.outputs.subscriptionIdSecretName] }}
      - shell: pwsh
        run: ./scripts/test.ps1 -Mode Validate -EnvironmentSuffix ${{ inputs.environment }}
```

## Cleanup Workflow (`cleanup.yml`) Specification

```yaml
name: Cleanup

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment to cleanup'
        required: true
        default: 'dev'
        type: choice
        options:
          - dev
          - uat

permissions:
  id-token: write
  contents: read

jobs:
  preview:
    name: Preview deletions
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Resolve Azure login secret names
        id: azure-login-secrets
        shell: pwsh
        env:
          AI_INFRA_ENV_YAML: ${{ secrets.AI_INFRA_ENV_YAML }}
        run: |
          # Reads githubAzure*SecretName values from variables/<environment>.yaml content.
      - uses: azure/login@v3
        with:
          client-id: ${{ secrets[steps.azure-login-secrets.outputs.clientIdSecretName] }}
          tenant-id: ${{ secrets[steps.azure-login-secrets.outputs.tenantIdSecretName] }}
          subscription-id: ${{ secrets[steps.azure-login-secrets.outputs.subscriptionIdSecretName] }}
      - shell: pwsh
        run: ./scripts/cleanup.ps1 -EnvironmentSuffix ${{ inputs.environment }} -WhatIf

  destroy:
    name: Delete resource groups
    needs: preview
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: azure/login@v3
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - shell: pwsh
        run: ./scripts/cleanup.ps1 -EnvironmentSuffix ${{ inputs.environment }} -Force
```

## Required Repository Secrets

| Secret Name | Required By | Description |
|---|---|---|
| Value of `githubAzureClientIdSecretName` in `variables/<environment>.yaml` | `azure/login@v3` | OIDC Entra ID Application (client) ID; default name `AZURE_CLIENT_ID` |
| Value of `githubAzureTenantIdSecretName` in `variables/<environment>.yaml` | `azure/login@v3` | Microsoft Entra ID Tenant ID; default name `AZURE_TENANT_ID` |
| Value of `githubAzureSubscriptionIdSecretName` in `variables/<environment>.yaml` | `azure/login@v3` | Azure Subscription ID; default name `AZURE_SUBSCRIPTION_ID` |
| `VM_ADMIN_PASSWORD` | `deploy` job | Password for the VM local administrator |

Use alternate secret names such as `AZURE_CLIENT_ID_01`, `AZURE_TENANT_ID_01`, and `AZURE_SUBSCRIPTION_ID_01` by changing the corresponding `githubAzure*SecretName` values in the environment YAML whose full contents are stored in `AI_INFRA_ENV_YAML`.

## Related Documentation

- [CI/CD & Public Repository Security](ci-cd-security.md)
- [Azure DevOps Pipelines Documentation](azure-pipelines.md)
- [Documentation Index](index.md)
