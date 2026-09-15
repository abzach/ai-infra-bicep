# GitHub Actions Workflows

This document details the consolidated GitHub Actions workflows for deployment and cleanup in `.github/workflows/`.

## Consolidated Architecture

The repository provides two unified workflows with runtime environment selection (`dev` or `uat`), replacing individual per-environment workflow files:

1. **Deploy Workflow (`.github/workflows/deploy.yml`):** Runs What-If planning, deploys Bicep infrastructure, configures Key Vault secrets, bootstraps the Jumpbox VM, and executes post-deployment validation tests.
2. **Cleanup Workflow (`.github/workflows/cleanup.yml`):** Runs What-If resource group deletion preview and performs guarded environment cleanup.

## Workflow Overview

| Workflow File | Trigger | Runtime Inputs | Stages / Jobs | Description |
|---|---|---|---|---|
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
      - uses: azure/login@v3
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - shell: pwsh
        run: ./scripts/deploy.ps1 -EnvironmentSuffix ${{ inputs.environment }} -WhatIf

  deploy:
    name: Deploy
    needs: planning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: azure/login@v3
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
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
      - uses: azure/login@v3
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
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
      - uses: azure/login@v3
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
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
| `AZURE_CLIENT_ID` | `azure/login@v3` | OIDC Entra ID Application (client) ID |
| `AZURE_TENANT_ID` | `azure/login@v3` | Microsoft Entra ID Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | `azure/login@v3` | Azure Subscription ID |
| `VM_ADMIN_PASSWORD` | `deploy` job | Password for the VM local administrator |

## Related Documentation

- [CI/CD & Public Repository Security](ci-cd-security.md)
- [Azure DevOps Pipelines Documentation](azure-pipelines.md)
- [Documentation Index](index.md)
