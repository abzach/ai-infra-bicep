# Azure Database for PostgreSQL Flexible Server

Deployed by [`bicep/modules/postgresflexibleserver.bicep`](../bicep/modules/postgresflexibleserver.bicep)
and orchestrated by `bicep/templates/main.bicep` when `deployPostgres` is `true`. The server is
sized to stay within the Azure free-tier allowance for this service.

## Configuration

| Setting | Value | Reason |
|---|---|---|
| Deployment option | Flexible Server | Only Flexible Server offers the Burstable tier and Stop/Start. |
| Compute tier | Burstable | The only tier eligible for the free-tier compute allowance. |
| Compute SKU | `Standard_B1ms` (`postgresSkuName`) | Smallest Burstable SKU; stays within the ~750 hours/month allowance for one server. |
| Storage | 32 GiB (`postgresStorageSizeGB`) | Matches the free-tier storage allowance; storage auto-grow is disabled so usage cannot silently exceed it. |
| Backup retention | 7 days (`postgresBackupRetentionDays`) | Minimum retention; backup storage stays within the free-tier backup allowance. |
| Backup redundancy | Locally redundant (`geoRedundantBackup: Disabled`) | Geo-redundant backups are outside the free-tier allowance. |
| High availability | Disabled | A standby server is a separately billed additional server. |
| Networking | VNet-integrated (delegated subnet), no public endpoint | Matches the repository's private-by-default posture; avoids a separate public IP/private endpoint cost. |
| Authentication | Password (`postgresAdminUsername` / generated password) | PostgreSQL Flexible Server does not have Microsoft Graph-backed principal name lookup available in Bicep, so Microsoft Entra-only admin mapping is not used here. |

## Networking

`network.bicep` creates a `postgres` subnet (`postgresSubnetAddressPrefix`, default `10.0.3.0/24`)
delegated to `Microsoft.DBforPostgreSQL/flexibleServers`, plus a
`privatelink.postgres.database.azure.com` private DNS zone linked to the VNet. Both are created
only when `deployPostgres` is `true`.

## Credentials

`deploy.ps1` generates the administrator password on first deploy and stores it in Key Vault as
the `postgres-admin-password` secret through Azure Resource Manager (the same ARM-only pattern
used for every other secret in this repository — see [Key Vault](key-vault.md)). Reruns reuse the
stored password instead of rotating it.

## Disabling this component

Set `deployPostgres: false` in the environment YAML to remove the server, its delegated subnet,
and its private DNS zone on the next deploy.

## Cross-Codebase Links

- [Root README](../README.md)
- [Architecture Documentation Index](README.md)
- [Bicep Modules](../bicep/modules/README.md)
- [Environment Configuration](../variables/README.md)
