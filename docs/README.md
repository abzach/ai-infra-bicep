# Enterprise Azure AI Foundry Architecture Documentation

Welcome to the comprehensive technical documentation for the Enterprise Azure AI Foundry Bicep infrastructure, deployment orchestration, CI/CD pipelines, and application stack.

## Documentation Catalog

### Security & CI/CD Governance
- [CI/CD & Public Repository Security](ci-cd-security.md): Threat model, OIDC authentication, GitHub secrets, and public repository safety.
- [GitHub Actions Workflows](github-actions.md): Consolidated deployment and cleanup workflows with runtime environment selection.
- [Azure DevOps Pipelines](azure-pipelines.md): Multi-stage deployment and guarded cleanup pipelines.

### Azure Deployed Resources
- [Resource Groups](resource-groups.md): Dual resource group topology (`Core` and `Network`), tagging schema, and lifecycle management.
- [Virtual Network & Networking](virtual-network.md): Virtual Network, subnets, Network Security Group, Public IP, and Private DNS Zones.
- [User-Assigned Managed Identities](managed-identity.md): AI Hub and Jumpbox VM identities and client ID resolution.
- [Role-Based Access Control (RBAC)](role-based-access-control.md): Resource-scoped least-privilege role assignment matrix.
- [Azure Storage Account](storage-account.md): Private Storage Account, blob soft-delete, and artifact containers.
- [Azure Key Vault](key-vault.md): Private RBAC-enabled Key Vault, soft-delete, and ARM secret provisioning.
- [Azure OpenAI Service](azure-openai.md): S0 account, Entra ID enforcement, diagnostic logging, and dual model deployments (`gpt-4.1-mini`, `gpt-4.1-nano`).
- [Private Endpoints](private-endpoints.md): Private Link endpoints, subnet attachment, and DNS zone group mapping.
- [Azure AI Foundry Hub](ai-hub.md): AI Hub workspace, user-assigned identity, and native Azure OpenAI connection.
- [Azure AI Foundry Project](ai-project.md): Child AI Project workspace for developer experiments.
- [Log Analytics Workspace](log-analytics.md): Centralized audit and operational diagnostics logging.
- [Windows Jumpbox VM](virtual-machine.md): Windows 11 jumpbox VM, Trusted Launch, extensions, and DevTestLab auto-shutdown.

### Application Stack
- [Python Terminal Chat Application](chat-application.md): Dual-persona (`Keith` & `Tim`) terminal app, parallel model inference, Rich UI, and token authentication.

## Architecture Diagram

```
Subscription
 ├── rg-<baseName>-network-<env>-<suffix>
 │     ├── VNet (10.0.0.0/16)
 │     │     ├── Services Subnet (10.0.1.0/24) ─── Private Endpoints (Blob, KV, OpenAI, AI Hub)
 │     │     └── VM Subnet (10.0.2.0/24) ──────── Jumpbox VM (10.0.2.4)
 │     ├── NSG (Deny-All RDP + IP Whitelist)
 │     ├── Static Public IP & Accelerated NIC
 │     └── Private DNS Zones (Vault, OpenAI, Blob, AzureML)
 └── rg-<baseName>-core-<env>-<suffix>
       ├── Azure AI Foundry Hub (with OpenAI Connection)
       ├── Azure AI Foundry Project
       ├── Azure OpenAI Account (gpt-4.1-mini & gpt-4.1-nano)
       ├── Azure Key Vault (RBAC, Soft-Delete)
       ├── Azure Storage Account (StorageV2, Private Container)
       ├── Log Analytics Workspace (Diagnostics Sink)
       ├── Windows 11 Jumpbox VM (Trusted Launch, Antimalware, ADE, AMA)
       └── User-Assigned Managed Identities (Hub & VM)
```

## Cross-Codebase Links

- [Root README](../README.md)
- [Root Navigation Index](../index.md)
- [Bicep Modules](../bicep/modules/README.md)
- [Bicep Templates](../bicep/templates/README.md)
- [Scripts Overview](../scripts/README.md)
- [App Overview](../app/README.md)
- [Pipelines Overview](../pipelines/README.md)
- [Workflows Overview](../.github/workflows/README.md)
- [Variables Overview](../variables/README.md)
