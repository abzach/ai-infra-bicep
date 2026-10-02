# Azure App Service

Deployed by [`bicep/modules/appservice.bicep`](../bicep/modules/appservice.bicep) and orchestrated by `bicep/templates/main.bicep` when `deployAppService` is `true`. The module creates a Linux App Service plan and web app for lightweight application hosting.

## Target $0 configuration

| Setting | Target | Reason |
|---|---|---|
| App Service plan SKU | F1 Free | Keeps the component within the App Service free-tier target. |
| Operating system | Linux | Hosts the configured Python runtime. |
| Runtime | Python 3.12 | Provides the application runtime without storing deployment credentials in infrastructure code. |
| HTTPS | Required | Redirects application traffic to TLS. |
| Minimum TLS | 1.2 | Rejects older TLS protocol versions. |
| FTP/FTPS | Disabled | Removes an unused credential-based deployment surface. |

## Network and data boundary

The F1 Free plan does not support private endpoints or VNet integration. This web app is therefore a deliberately public surface, like Static Web Apps. Do not place secrets, private data, or private backend addresses in application content or settings. Use managed identity and a paid network-capable plan only after an explicit design change if the app must reach private services.

## Lifecycle

- Set `deployAppService: true` in the environment YAML to deploy and maintain the App Service plan and app.
- Set `deployAppService: false` to remove the app first and then its plan on the next deployment.
- Keep `appServiceSkuName` at `F1` while the repository targets the free tier.

## Cross-Codebase Links

- [Root README](../README.md)
- [Architecture Documentation Index](README.md)
- [Documentation Index](index.md)
- [Bicep Modules](../bicep/modules/README.md)
- [Variables](../variables/README.md)
