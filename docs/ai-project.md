# Microsoft Foundry Project

The project is a child of the `AIServices` Foundry account and is supported by the current Microsoft Foundry portal.

| Setting | Value |
|---|---|
| Resource type | `Microsoft.CognitiveServices/accounts/projects` |
| Identity | System-assigned |
| Network posture | Inherited from the private Foundry account |
| Capability host | `agents` with kind `Agents` |

The project owns AAD connections to Storage, Cosmos DB, and Azure AI Search. Its capability host binds those connections for file storage, thread storage, and vector stores, keeping Agent data in tenant-owned resources.

The project identity receives resource-scoped roles for model access and Agent backing stores. Configured administrators receive `Foundry Owner` at account scope and `Foundry Project Manager` at project scope. Configured users receive `Foundry User` and `Foundry Agent Consumer` at project scope.

## Related documentation

- [Microsoft Foundry Account and Agent Service](foundry-account.md)
- [Azure AI Search](ai-search.md)
- [Role-Based Access Control](role-based-access-control.md)
