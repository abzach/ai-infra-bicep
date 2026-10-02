# Windows Jumpbox Virtual Machine

This document details the configuration, security profile, extensions, scheduled auto-shutdown, and application bootstrap for the Windows Jumpbox VM provisioned by `bicep/modules/vm.bicep`.

## Deployment flag

This component is controlled by `deployVm` in your environment YAML. When set to `false`, the next `scripts/deploy.ps1` run removes the auto-shutdown schedule, the VM, the OS disk, the NIC, the public IP, and the NSG, and skips application bootstrap and password handling.

The VM admin password is never rotated on a rerun. A new password is issued only on first deploy, when a Spot/Regular priority change forces VM recreation, or when `deploy.ps1` is run with `-RotateVmPassword`.

## Resource Overview

The Windows 11 Enterprise Jumpbox VM operates inside the private virtual network (`10.0.2.0/24`) and hosts the dual-persona Python AI chat application. It provides developers and administrators with secure desktop and terminal access to private PaaS resources without opening those services to the public internet.

- **Resource Name:** `vm-<baseName>-<environmentSuffix>`
- **Resource Type:** `Microsoft.Compute/virtualMachines@2024-03-01`
- **Size:** `vmSize` from your environment YAML; it must support Azure Disk Encryption, so `scripts/config.ps1` rejects L-family (storage-optimized) sizes for image-based deployments
- **Public DNS Name:** Optional `vmPublicIpDnsNameLabel` on the VM public IP; for example `az-swe-aifp` in `swedencentral` creates `az-swe-aifp.swedencentral.cloudapp.azure.com`

## Important Configuration Settings

| Setting / Property | Configured Value | Description / Security Impact |
|---|---|---|
| **OS Image Publisher** | `microsoftwindowsdesktop` | Windows Client image publisher |
| **OS Image Offer** | `windows-ent-cpc` | Windows Enterprise Cloud PC image |
| **OS Image SKU** | `vmImageSku` from your environment YAML | Windows client image SKU |
| **OS Image Version** | `latest` | Latest marketplace image release |
| **OS Disk Storage Tier** | `Standard_LRS` | Managed OS disk storage type |
| **License Type** | `Windows_Client` | Azure Hybrid Benefit for Windows Client licensing |
| **Security Type** | `TrustedLaunch` | Enables Trusted Launch security profile |
| **Secure Boot** | `true` | Protects bootloaders against rootkits |
| **vTPM** | `true` | Enables virtual Trusted Platform Module |
| **Identity Type** | `UserAssigned` | Single shared identity (no SystemAssigned) used by the Python Chat App and Automation |
| **Public IP DNS Label** | `vmPublicIpDnsNameLabel` from your environment YAML | Optional public DNS label for RDP convenience; leave empty to skip DNS |
| **RDP Allowlist** | Stable `allow-rdp-user` plus temporary `allow-rdp-deployer` | User sources come from environment YAML; `main.ps1 dev-connect` / `uat-connect` refresh access, and Automation removes only the deployer rule weekly |
| **Spot VM Capability** | `true` (Dev) / `false` (UAT) | Uses interruptible capacity to minimize compute cost |
| **Spot Max Price** | `-1` | Bids up to on-demand pricing |
| **Patch Mode** | `AutomaticByOS` | Automatic Windows guest OS updates |

## Attach-mode OS disk (migration support)

`bicep/modules/vm.bicep` accepts an optional `existingOsDiskId` (and `osType`, default `Windows`) parameter. When set, the VM is created with `storageProfile.osDisk.createOption: 'Attach'` against that existing managed disk instead of `FromImage`, and the `osProfile` block (computer name, admin username/password, patch settings) is omitted entirely — ARM rejects `osProfile` together with `createOption: Attach`.

This exists specifically to let a previously-deployed VM's OS disk survive a resource-group rename: detach the disk from the old VM (`az vm update --set storageProfile.osDisk.deleteOption=Detach` then `az vm delete`), move the orphaned disk into the new resource group (`az resource move`), then redeploy with `vmExistingOsDiskId` set to the disk's resource ID. The VM is deployed to the foundation resource group, so `scripts/config.ps1` rejects a `vmExistingOsDiskId` in any other group; `scripts/deploy.ps1` performs this delete/move automatically for a VM still in the workload group.

**Important:** because Attach mode skips `osProfile`, the VM's real admin credential remains whatever was already set on the disk — it is **not** the password `deploy.ps1` generates and stores in Key Vault. Once migrated this way, `vmExistingOsDiskId` should stay set permanently; do not clear it on a later deploy, or the VM would need to be recreated `FromImage` again (losing the disk's state).

Attach mode also omits the `AzureDiskEncryption` extension. The migrated disk retains its existing encryption state and remains dependent on the original Azure Disk Encryption Key Vault, BEK secret version, and private network path. Preserve or recover those dependencies before starting the reattached VM; deleting the source vault prevents the OS disk from unlocking and causes `DiskEncryptionInternalError`. Applying a new BitLocker workflow through a different Key Vault can also fail against an attached OS disk. Image-based VM deployments continue to configure Azure Disk Encryption.

## Virtual Machine Extensions

The VM template applies three managed extensions to ensure host security and compliance:

| Extension Name | Publisher / Type | Version | Purpose |
|---|---|---|---|
| **AzureMonitorWindowsAgent** | `Microsoft.Azure.Monitor` / `AzureMonitorWindowsAgent` | `1.0` | Ingests OS telemetry and heartbeats to Log Analytics |
| **IaaSAntimalware** | `Microsoft.Azure.Security` / `IaaSAntimalware` | `1.5` | Real-time antivirus protection and scheduled scans |
| **AzureDiskEncryption** | `Microsoft.Azure.Security` / `AzureDiskEncryption` | `2.2` | BitLocker-based disk encryption backed by Key Vault for image-based VM deployments |

## Scheduled Auto-Shutdown

To prevent unnecessary costs, the VM includes a DevTestLab auto-shutdown schedule (`Microsoft.DevTestLab/schedules@2018-09-15`):

| Property | Configured Value | Description |
|---|---|---|
| **Schedule Name** | `shutdown-computevm-<vmName>` | DevTestLab schedule resource name |
| **Status** | `Enabled` | Active schedule |
| **Task Type** | `ComputeVmShutdownTask` | Shuts down and deallocates compute resources |
| **Daily Recurrence Time** | `0300` (03:00 AM) | Scheduled time in 24-hour format |
| **Time Zone** | `vmAutoShutdownTimeZone` from `variables/core.yaml` | Time zone for the shutdown schedule |

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
