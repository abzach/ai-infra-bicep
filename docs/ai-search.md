# Azure AI Search

Azure AI Search provides vector-store persistence for Microsoft Foundry Agent Service.

## Configuration

| Setting | Value |
|---|---|
| Resource type | `Microsoft.Search/searchServices` |
| SKU | `aiSearchSkuName` from configuration (`standard`) |
| Public network access | Disabled |
| Local authentication | Disabled |
| Authentication | Microsoft Entra ID |
| Private endpoint group | `searchService` |
| Private DNS zone | `privatelink.search.windows.net` |

The Foundry project identity receives `Search Index Data Contributor` and `Search Service Contributor`. The project connection uses AAD authentication and is referenced by the Agent capability host as its vector-store connection.

## Related documentation

- [Microsoft Foundry Account and Agent Service](foundry-account.md)
- [Foundry Project](ai-project.md)
- [Private Endpoints](private-endpoints.md)