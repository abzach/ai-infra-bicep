# Enterprise Azure AI Foundry Architecture Documentation

Welcome to the comprehensive technical documentation for the Enterprise Azure AI Foundry Bicep infrastructure, deployment orchestration, CI/CD pipelines, and application stack.

## Documentation Catalog

### Security & CI/CD Governance
- [CI/CD & Public Repository Security](ci-cd-security.md): Threat model, OIDC authentication, GitHub secrets, and public repository safety.
- [GitHub Actions Workflows](github-actions.md): Consolidated deployment and cleanup workflows with runtime environment selection.
- [Azure DevOps Pipelines](azure-pipelines.md): Multi-stage deployment and guarded cleanup pipelines.

### Azure Deployed Resources
- [Resource Groups](resource-groups.md): Dual resource group topology (`Workload` and `Foundation`), tagging schema, and lifecycle management.
- [Virtual Network & Networking](virtual-network.md): Virtual Network, subnets, Network Security Group, Public IP, and Private DNS Zones.
- [User-Assigned Managed Identity](managed-identity.md): Shared identity used by the jumpbox, Automation, and application workloads; the new Foundry project uses its own system-assigned identity.
- [Role-Based Access Control (RBAC)](role-based-access-control.md): Resource-scoped least-privilege role assignment matrix.
- [Azure Storage Account](storage-account.md): Private Storage Account, blob soft-delete, and artifact containers.
- [Azure Key Vault](key-vault.md): Private RBAC-enabled Key Vault, soft-delete, and ARM secret provisioning.
- [Azure OpenAI Service](azure-openai.md): S0 account, Entra ID enforcement, diagnostic logging, and dual model deployments (`gpt-4.1-mini`, `gpt-4.1-nano`).
- [Private Endpoints](private-endpoints.md): Private Link endpoints, subnet attachment, and DNS zone group mapping.
- [Microsoft Foundry Account and Agent Service](foundry-account.md): Private `AIServices` account, network injection, Agent capability host, and migration lifecycle.
- [Microsoft Foundry Project](ai-project.md): Child project, backing-resource connections, and project identity.
- [Azure AI Search](ai-search.md): Private vector-store service for Agents.
- [Log Analytics Workspace](log-analytics.md): Centralized audit and operational diagnostics logging.
- [Windows Jumpbox VM](virtual-machine.md): Windows 11 jumpbox VM, Trusted Launch, attach-aware extensions, and DevTestLab auto-shutdown.
- [Azure Automation Account](automation-account.md): User-assigned identity, repository runbook publication, and daily VM start schedule.
- [Azure Database for PostgreSQL Flexible Server](postgresql.md): Free-tier-sized Burstable server, VNet-integrated, HA disabled.
- [Azure Static Web Apps](static-web-apps.md): Free-plan static hosting resource for a lightweight front end or documentation site.
- [Azure Cosmos DB](cosmos-db.md): Free-tier NoSQL account with private endpoint, disabled local auth, and provisioned throughput guardrails.
- [Azure API Management](api-management.md): Consumption-tier API gateway target for up to 1 million included monthly calls.
- [Azure App Service](app-service.md): Public Linux web app on the F1 Free plan, with HTTPS-only and TLS 1.2 enforcement.

### Application Stack
- [Python Terminal Chat Application](chat-application.md): Dual-persona (`Keith` & `Tim`) terminal app, parallel model inference, Rich UI, and token authentication.

## Architecture Diagram

```
Subscription
 ├── rg-<baseName>-foundation-<env>-<instance>
 │     ├── VNet (10.0.0.0/16)
 │     │     ├── Services Subnet (10.0.1.0/24) ─── Private Endpoints (Blob, KV, OpenAI, Foundry, Search, Cosmos DB)
 │     │     ├── VM Subnet (10.0.2.0/24) ──────── Jumpbox VM
 │     │     ├── PostgreSQL Subnet (10.0.3.0/24)
 │     │     └── Agent Subnet (10.0.4.0/24) ───── Microsoft.App/environments delegation
 │     ├── NSG (Deny-All RDP + IP Whitelist)
 │     ├── Static Public IP & Accelerated NIC
│     ├── Private DNS Zones (Vault, OpenAI, Foundry, Search, Blob, PostgreSQL, Cosmos DB)
│     ├── User-Assigned Managed Identity (VM, Automation, app data access)
 │     ├── Microsoft Foundry AIServices Account + Project + Agent Capability Host
 │     ├── Windows 11 Jumpbox VM + OS disk (Trusted Launch, Antimalware, AMA; ADE for image deployments)
 │     ├── Azure Automation Account (PowerShell runbooks, daily VM start)
 │     ├── Azure API Management (Consumption tier)
 │     └── Azure App Service plan + app (Linux, F1 Free)
 └── rg-<baseName>-workload-<env>-<instance>
      ├── Azure AI Search (private Agent vector store)
       ├── Azure OpenAI Account (gpt-4.1-mini & gpt-4.1-nano)
       ├── Azure Key Vault (RBAC, Soft-Delete)
       ├── Azure Storage Account (StorageV2, Private Container)
       ├── Log Analytics Workspace (Diagnostics Sink)
      ├── Azure Static Web App (Free plan)
      ├── Azure Cosmos DB for NoSQL (free tier, private endpoint)
       └── PostgreSQL Flexible Server (Burstable B1ms, 32 GiB, HA disabled, VNet-integrated)
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
