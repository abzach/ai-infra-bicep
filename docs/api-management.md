# Azure API Management

Deployed by [`bicep/modules/apimanagement.bicep`](../bicep/modules/apimanagement.bicep) and orchestrated by `bicep/templates/main.bicep` when `deployApiManagement` is `true`. The service is configured for the Consumption tier so it targets the serverless API gateway allowance with up to 1 million included calls per month.

## Configuration

| Setting | Value | Reason |
|---|---|---|
| Resource | Azure API Management | Managed API gateway for lightweight API fronting and policy experiments. |
| Pricing tier | `Consumption` (`apiManagementSkuName`) | Targets the free monthly call allowance; avoids fixed monthly Basic, Standard, and Premium charges. |
| Capacity | `0` | Required serverless capacity shape for the Consumption tier. |
| Monthly call target | Stay at or below 1,000,000 calls/month | Keeps usage within the free-call allowance for this tier. |
| Publisher email | `apiManagementPublisherEmail` | Contact metadata required by API Management. Replace the neutral default before production use. |
| Publisher name | `apiManagementPublisherName` | Display metadata required by API Management. |
| Network exposure | Public gateway surface | Consumption tier is not integrated into this repository's private endpoint model. Do not publish private APIs or secrets here without an explicit gateway design. |

## Free-tier guardrails

Use this shape when the goal is the free-call allowance:

```text
API Management -> Consumption tier -> <=1,000,000 API calls/month
```

Do not switch this component to Basic, Basic v2, Standard, Standard v2, Premium, or Premium v2 when the objective is the Consumption-tier allowance. `scripts/config.ps1` restricts `apiManagementSkuName` to `Consumption`, and `scripts/scan.ps1` verifies that the generated template keeps the service on Consumption.

## Disabling this component

Set `deployApiManagement: false` in the environment YAML to remove the API Management service on the next deploy.

## Cross-Codebase Links

- [Root README](../README.md)
- [Architecture Documentation Index](README.md)
- [Bicep Modules](../bicep/modules/README.md)
- [Environment Configuration](../variables/README.md)