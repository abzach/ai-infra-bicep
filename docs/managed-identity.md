# User-Assigned Managed Identities

This document covers the user-assigned managed identities deployed by `bicep/modules/managedidentity.bicep`.

## Architecture & Identity Isolation

The enterprise stack provisions three dedicated User-Assigned Managed Identities to isolate AI workspace, Jumpbox application, and scheduled Automation permissions:

1. **AI Hub Managed Identity (`mi-<baseName>-hub-<environmentSuffix>-<nameSuffix>`):** Assigned to the Azure AI Foundry Hub workspace.
2. **Jumpbox VM Managed Identity (`mi-<baseName>-vm-<environmentSuffix>-<nameSuffix>`):** Assigned to the Jumpbox Virtual Machine.
3. **Automation Managed Identity (`mi-<baseName>-automation-<environmentSuffix>-<nameSuffix>`):** Assigned to the Automation Account and selected explicitly by cloud runbooks.

```
                  ┌───────────────────────────────┐
                  │ mi-<baseName>-hub-<env>-<sfx> │
                  └──────────────┬────────────────┘
                                 │
                 ┌───────────────┼───────────────┐
                 ▼               ▼               ▼
           Storage Blob     Key Vault       Azure OpenAI
         Data Contributor  Secrets User         User
                 ▲               ▲               ▲
                 │               │               │
                 └───────────────┼───────────────┘
                                 │
                  ┌──────────────┴────────────────┐
                  │  mi-<baseName>-vm-<env>-<sfx> │
                  └───────────────────────────────┘
```

## Template Configuration

| Resource Name Pattern | Resource Type | Location | Description |
|---|---|---|---|
| `mi-<baseName>-hub-<env>-<suffix>` | `Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31` | Target Region | Identity assigned to Azure AI Foundry Hub |
| `mi-<baseName>-vm-<env>-<suffix>` | `Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31` | Target Region | Identity assigned to Jumpbox VM for Python app |
| `mi-<baseName>-automation-<env>-<suffix>` | `Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31` | Target Region | Identity assigned to the Automation Account for scheduled runbooks |

## Runtime Identity Resolution

- **Jumpbox VM:** The VM has both System-Assigned and User-Assigned identities attached. The Python Chat App explicitly sets `AZURE_CLIENT_ID` in its `.env` pointing to the VM User-Assigned Identity's Client ID. `DefaultAzureCredential` uses this Client ID to request access tokens directly for `https://cognitiveservices.azure.com/.default`.
- **AI Hub:** The AI Hub workspace references `hubManagedIdentityId` as its `primaryUserAssignedIdentity`, allowing the Hub to access backing Key Vault and Storage resources securely without credentials.
- **Automation Account:** The `schedule-vm-start` runbook receives the Automation identity client ID as a schedule parameter and passes it to `Connect-AzAccount -Identity -AccountId`, avoiding ambiguity when selecting an Azure identity.

## Related Documentation

- [Role-Based Access Control Documentation](role-based-access-control.md)
- [AI Hub Documentation](ai-hub.md)
- [Virtual Machine Documentation](virtual-machine.md)
- [Chat Application Documentation](chat-application.md)
- [Automation Account Documentation](automation-account.md)
- [Documentation Index](index.md)
