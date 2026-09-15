# Windows Jumpbox Virtual Machine

This document details the configuration, security profile, extensions, scheduled auto-shutdown, and application bootstrap for the Windows Jumpbox VM provisioned by `bicep/modules/vm.bicep`.

## Resource Overview

The Windows 11 Enterprise Jumpbox VM operates inside the private virtual network (`10.0.2.0/24`) and hosts the dual-persona Python AI chat application. It provides developers and administrators with secure desktop and terminal access to private PaaS resources without opening those services to the public internet.

- **Resource Name:** `vm-<baseName>-<environmentSuffix>-<nameSuffix>`
- **Resource Type:** `Microsoft.Compute/virtualMachines@2024-03-01`
- **Default Size:** `Standard_L2as_v4`

## Important Configuration Settings

| Setting / Property | Configured Value | Description / Security Impact |
|---|---|---|
| **OS Image Publisher** | `microsoftwindowsdesktop` | Windows Client image publisher |
| **OS Image Offer** | `windows-ent-cpc` | Windows Enterprise Cloud PC image |
| **OS Image SKU** | `win11-24h2-ent-cpc-m365` | Windows 11 Enterprise 24H2 with Microsoft 365 apps |
| **OS Image Version** | `latest` | Latest marketplace image release |
| **OS Disk Storage Tier** | `Standard_LRS` | Managed OS disk storage type |
| **License Type** | `Windows_Client` | Azure Hybrid Benefit for Windows Client licensing |
| **Security Type** | `TrustedLaunch` | Enables Trusted Launch security profile |
| **Secure Boot** | `true` | Protects bootloaders against rootkits |
| **vTPM** | `true` | Enables virtual Trusted Platform Module |
| **Identity Type** | `SystemAssigned, UserAssigned` | Dual identity; User-Assigned used by Python Chat App |
| **Spot VM Capability** | `true` (Dev) / `false` (UAT) | Uses interruptible capacity to minimize compute cost |
| **Spot Max Price** | `-1` | Bids up to on-demand pricing |
| **Patch Mode** | `AutomaticByOS` | Automatic Windows guest OS updates |

## Virtual Machine Extensions

The VM template applies three managed extensions to ensure host security and compliance:

| Extension Name | Publisher / Type | Version | Purpose |
|---|---|---|---|
| **AzureMonitorWindowsAgent** | `Microsoft.Azure.Monitor` / `AzureMonitorWindowsAgent` | `1.0` | Ingests OS telemetry and heartbeats to Log Analytics |
| **IaaSAntimalware** | `Microsoft.Azure.Security` / `IaaSAntimalware` | `1.5` | Real-time antivirus protection and scheduled scans |
| **AzureDiskEncryption** | `Microsoft.Azure.Security` / `AzureDiskEncryption` | `2.2` | BitLocker-based disk encryption backed by Key Vault |

## Scheduled Auto-Shutdown

To prevent unnecessary costs, the VM includes a DevTestLab auto-shutdown schedule (`Microsoft.DevTestLab/schedules@2018-09-15`):

| Property | Configured Value | Description |
|---|---|---|
| **Schedule Name** | `shutdown-computevm-<vmName>` | DevTestLab schedule resource name |
| **Status** | `Enabled` | Active schedule |
| **Task Type** | `ComputeVmShutdownTask` | Shuts down and deallocates compute resources |
| **Daily Recurrence Time** | `0300` (03:00 AM) | Scheduled time in 24-hour format |
| **Time Zone** | `India Standard Time` | Local reference timezone |

## Application Bootstrapping

The VM is bootstrapped post-deployment using `az vm run-command invoke`:
1. Installs Python, dependencies, and configuration in `C:\ChatApp\`.
2. Generates desktop launcher shortcut `AI Chat`.
3. Stores environment variables in `C:\ChatApp\.env` configured with the VM's User-Assigned Managed Identity client ID.

## Related Documentation

- [Chat Application Documentation](chat-application.md)
- [Managed Identity Documentation](managed-identity.md)
- [Virtual Network Documentation](virtual-network.md)
- [Key Vault Documentation](key-vault.md)
- [Documentation Index](index.md)
