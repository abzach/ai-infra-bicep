# Azure Static Web Apps

Deployed by [`bicep/modules/staticwebapp.bicep`](../bicep/modules/staticwebapp.bicep) and orchestrated by `bicep/templates/main.bicep` when `deployStaticWebApp` is `true`. Azure Static Web Apps is a good fit when this environment needs a static front end, documentation site, or lightweight web UI.

## Target $0 configuration

| Setting | Target | Reason |
|---|---|---|
| Resource | Azure Static Web Apps | Managed static hosting with integrated GitHub and Azure DevOps deployment support. |
| Hosting plan | Free | Microsoft positions the Free plan for personal projects, and the pricing page lists it at $0. |
| SKU | Free | Avoids Standard-plan charges. |
| Included bandwidth | 100 GB per subscription per month | Matches the documented Free-plan monthly bandwidth quota. |
| Storage | Stay within 500 MB total per app across environments and 250 MB per environment | Keeps the app within the Free-plan Static Web Apps quota. |
| Custom domains | Up to 2 per app | Included in the Free hosting plan. |
| SSL certificates | Free, automatically renewing | Provided for the generated hostname and custom domains. |
| Standard plan | Do not select for a strict $0 target | Standard is intended for production apps and includes billed capabilities. |
| Azure Front Door | Do not add for a strict $0 target | It is a separate service with its own billing model. |

## Recommended setup

Use this shape when the objective is a no-cost static site:

```text
Static Web App -> Free plan -> <=500 MB total app storage -> <=100 GB bandwidth per subscription/month -> <=2 custom domains/app
```

During resource creation, the key selection is **Plan type: Free**. Do not select Standard unless the app needs Standard-only capabilities such as private endpoints, custom authentication registrations, IP restrictions, custom roles through functions, an SLA, or higher limits.

## Notes for this repository

- Static Web Apps Free does not support private endpoints, so this component is a public static-hosting surface. Do not place secrets or private data in the app content.
- Do not add Azure Front Door only to front this app when the goal is strictly $0.
- Set `deployStaticWebApp: false` in the environment YAML to remove the Static Web App on the next deploy.
- `scripts/scan.ps1` verifies that the deployed template keeps this resource on the Free SKU.

## References

- [Azure Static Web Apps hosting plans](https://learn.microsoft.com/azure/static-web-apps/plans)
- [Quotas in Azure Static Web Apps](https://learn.microsoft.com/azure/static-web-apps/quotas)
- [Azure Static Web Apps pricing](https://azure.microsoft.com/pricing/details/app-service/static/)

## Cross-Codebase Links

- [Root README](../README.md)
- [Architecture Documentation Index](README.md)
- [Documentation Index](index.md)