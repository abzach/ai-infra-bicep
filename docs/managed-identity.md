# User-Assigned Managed Identity

This document covers the single shared user-assigned managed identity deployed by `bicep/modules/managedidentity.bicep`.

## Architecture & Accepted Trade-off

The enterprise stack provisions exactly **one** User-Assigned Managed Identity (`mi-<baseName>-<environmentSuffix>`), deployed into the foundation resource group, and reused across every resource that needs an identity: the AI Foundry Hub, the AI Foundry Project, the Jumpbox VM, and the Automation Account. No resource in this stack uses a SystemAssigned identity.

This is a deliberate simplification over per-resource identity isolation: a single identity holds the union of all roles below, so compromising any one resource that uses it exposes every role granted to it. This trade-off was chosen intentionally to reduce operational overhead; it removes the blast-radius isolation that separate per-resource identities would provide.

```
                  ┌───────────────────────────────┐
                  │      mi-<baseName>-<env>      │
                  │   (foundation resource group) │
                  └──────────────┬────────────────┘
                                 │
                 ┌───────────────┼───────────────┬───────────────┐
                 ▼               ▼               ▼               ▼
           Storage Blob     Key Vault       Azure OpenAI    Virtual Machine
         Data Contributor  Secrets User         User          Contributor
                                                              (self, via Automation)
```

## Template Configuration

| Resource Name Pattern | Resource Type | Location | Description |
|---|---|---|---|
| `mi-<baseName>-<env>` | `Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31` | Foundation resource group | Single identity assigned to the AI Hub, AI Project, Jumpbox VM, and Automation Account |

## Runtime Identity Resolution

- **Jumpbox VM:** The VM has only the shared User-Assigned identity attached (no SystemAssigned identity). The Python Chat App explicitly sets `AZURE_CLIENT_ID` in its `.env` pointing to the shared identity's Client ID. `DefaultAzureCredential` uses this Client ID to request access tokens directly for `https://cognitiveservices.azure.com/.default`.
- **AI Hub and AI Project:** Both workspaces reference the shared identity as their `primaryUserAssignedIdentity`, allowing them to access backing Key Vault and Storage resources securely without credentials.
- **Automation Account:** The `schedule-vm-start` runbook receives the shared identity's client ID as a schedule parameter and passes it to `Connect-AzAccount -Identity -AccountId`, avoiding ambiguity when selecting an Azure identity. The identity also holds Virtual Machine Contributor over the jumpbox VM so the automation runbooks can start/stop it and manage its NSG rules — note that this means the same identity used *by* the VM also has management rights *over* the VM.

## Related Documentation

- [Role-Based Access Control Documentation](role-based-access-control.md)
- [AI Hub Documentation](ai-hub.md)
- [Virtual Machine Documentation](virtual-machine.md)
- [Chat Application Documentation](chat-application.md)
- [Automation Account Documentation](automation-account.md)
- [Documentation Index](index.md)
