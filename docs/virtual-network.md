# Virtual Network & Networking Infrastructure

This document details the private networking topology defined in `bicep/modules/network.bicep`.

## Architecture Overview

The network module provisions a secured Virtual Network (VNet) with isolated subnets, network security rules, network interfaces, public IP, and integrated Private DNS Zones.

### Key Components:
- **Virtual Network:** `vnet-<baseName>-<environmentSuffix>-<nameSuffix>`
- **Subnets:**
  - `services` (`10.0.1.0/24`): Hosts Private Endpoints for Key Vault, Storage Blob, Azure OpenAI, and AI Hub.
  - `vm` (`10.0.2.0/24`): Hosts the Jumpbox VM Network Interface.
- **Network Security Group (NSG):** `vm-<baseName>-<environmentSuffix>-<nameSuffix>-nsg`
- **Public IP:** `vm-<baseName>-<environmentSuffix>-<nameSuffix>-pip` (Standard SKU, Static allocation, optional DNS label)
- **Private DNS Zones:** Linked to the VNet with automatic internal name resolution.

## Important Configurations

| Property / Resource | Configured Value | Description |
|---|---|---|
| **VNet Address Space** | `10.0.0.0/16` | Top-level IPv4 address space |
| **Services Subnet** | `10.0.1.0/24` | Private Endpoint Subnet (`privateEndpointNetworkPolicies: Disabled`, `privateLinkServiceNetworkPolicies: Enabled`) |
| **Service Endpoints** | `Microsoft.CognitiveServices`, `Microsoft.KeyVault`, `Microsoft.Storage` | Configured on services subnet |
| **VM Subnet** | `10.0.2.0/24` | Subnet dedicated to Jumpbox VM |
| **Public IP SKU** | `Standard` | Static allocation for Jumpbox VM public IP |
| **Public IP DNS Label** | `vmPublicIpDnsNameLabel` from environment YAML | Optional label for `<label>.<region>.cloudapp.azure.com`; for example `az-swe-aifp` in `swedencentral` creates `az-swe-aifp.swedencentral.cloudapp.azure.com` |
| **NIC Accelerated Networking** | `true` | Enabled on the VM Network Interface (`vmAcceleratedNetworking`) |
| **NSG Default Deny RDP** | `Deny` / Priority `4096` | Blocks all inbound RDP (`TCP 3389`) from any source (`*`) |
| **NSG Explicit RDP Whitelist** | Priority `200+` | `allow-rdp-user` holds environment YAML sources; `allow-rdp-deployer` holds the temporary detected source and is deleted weekly. `main.ps1 dev-connect` / `uat-connect` refresh these rules without deployment. |

### Private DNS Zones & VNet Links

The module creates four core Private DNS zones in the global location and links them to the VNet (`registrationEnabled: false`):

| Private DNS Zone Name | Targeted Service | VNet Link Name |
|---|---|---|
| `privatelink.vaultcore.azure.net` | Azure Key Vault | `vnet-link` |
| `privatelink.openai.azure.com` | Azure OpenAI Service | `vnet-link` |
| `privatelink.blob.core.windows.net` | Azure Blob Storage | `vnet-link` |
| `privatelink.api.azureml.ms` | Azure AI Foundry / Azure ML Workspace | `vnet-link` |

## Security Invariants

1. **Deny-All RDP Perimeter:** Inbound RDP (`3389`) is blocked by default with priority `4096`. Inbound rules are only created for specific IP ranges detected or configured at deploy time, or added later with `scripts/rdp.ps1`.
2. **Private Link DNS Integration:** All PaaS service endpoints resolve to internal private IP addresses on the `services` subnet (`10.0.1.0/24`), preventing data-plane traffic from leaving Azure's private backbone.

## Related Documentation

- [Private Endpoints Documentation](private-endpoints.md)
- [Virtual Machine Documentation](virtual-machine.md)
- [Resource Groups Documentation](resource-groups.md)
- [Documentation Index](index.md)
