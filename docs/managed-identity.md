# User-Assigned Managed Identities

This document covers the user-assigned managed identities deployed by `bicep/modules/managedidentity.bicep`.

## Architecture & Identity Isolation

The enterprise stack provisions two dedicated User-Assigned Managed Identities to separate AI workspace control plane tasks from the Jumpbox VM chat client:

1. **AI Hub Managed Identity (`mi-<baseName>-hub-<environmentSuffix>-<nameSuffix>`):** Assigned to the Azure AI Foundry Hub workspace.
2. **Jumpbox VM Managed Identity (`mi-<baseName>-vm-<environmentSuffix>-<nameSuffix>`):** Assigned to the Jumpbox Virtual Machine.

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

## Runtime Identity Resolution

- **Jumpbox VM:** The VM has both System-Assigned and User-Assigned identities attached. The Python Chat App explicitly sets `AZURE_CLIENT_ID` in its `.env` pointing to the VM User-Assigned Identity's Client ID. `DefaultAzureCredential` uses this Client ID to request access tokens directly for `https://cognitiveservices.azure.com/.default`.
- **AI Hub:** The AI Hub workspace references `hubManagedIdentityId` as its `primaryUserAssignedIdentity`, allowing the Hub to access backing Key Vault and Storage resources securely without credentials.

## Related Documentation

- [Role-Based Access Control Documentation](role-based-access-control.md)
- [AI Hub Documentation](ai-hub.md)
- [Virtual Machine Documentation](virtual-machine.md)
- [Chat Application Documentation](chat-application.md)
- [Documentation Index](index.md)
