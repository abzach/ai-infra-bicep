# rdp.ps1 — Adds configured RDP source CIDRs to the jumpbox NSG.
#
# EXAMPLES
#   # Apply rdpAllowedPublicIpAddress and rdpAllowedIpCidrs from variables/dev.yaml
#   .\rdp.ps1 -EnvironmentSuffix dev
#
#   # Add the current workstation public IP for this run
#   .\rdp.ps1 -EnvironmentSuffix dev -UseCurrentPublicIp
#
#   # Add one explicit address or CIDR without editing YAML
#   .\rdp.ps1 -EnvironmentSuffix dev -IpAddress 203.0.113.10
#   .\rdp.ps1 -EnvironmentSuffix dev -IpCidr 203.0.113.10/32

param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'uat')]
    [string] $EnvironmentSuffix,

    [string] $IpAddress,

    [string] $IpCidr,

    [switch] $UseCurrentPublicIp,

    [switch] $WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CurrentScriptRoot {
    $commandDefinition = if ($MyInvocation.MyCommand) { $MyInvocation.MyCommand.Definition } else { $null }

    $candidateRoots = @(
        $PSScriptRoot,
        $(if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { Split-Path -Parent $PSCommandPath } else { $null }),
        $(if (-not [string]::IsNullOrWhiteSpace($commandDefinition) -and (Test-Path $commandDefinition)) { Split-Path -Parent ((Resolve-Path $commandDefinition).Path) } else { $null })
    )

    foreach ($candidateRoot in $candidateRoots) {
        if (-not [string]::IsNullOrWhiteSpace($candidateRoot)) {
            return $candidateRoot
        }
    }

    throw 'Unable to resolve the script root for rdp.ps1.'
}

$scriptRoot = Get-CurrentScriptRoot

. (Join-Path $scriptRoot 'config.ps1')
. (Join-Path $scriptRoot 'common.ps1')

Initialize-ScriptLogging -ScriptRoot $scriptRoot -ScriptName 'rdp.ps1'
trap { Write-LogEntry -Level 'ERROR' -Message "Unhandled error: $($_.Exception.Message)"; Write-ScriptTimingSummary -Status 'failed' }

function Convert-ToBoolean {
    param(
        [Parameter(Mandatory)] [object] $Value,
        [bool] $Default = $false
    )

    if ($null -eq $Value) {
        return $Default
    }

    $text = $Value.ToString().Trim().ToLower()
    if ($text -in @('true', '1', 'yes', 'y')) { return $true }
    if ($text -in @('false', '0', 'no', 'n')) { return $false }
    return $Default
}

function Convert-ToIpv4SourceAddress {
    param([Parameter(Mandatory)] [string] $Value)

    $text = $Value.Trim()
    $parts = $text -split '/', 2
    $addressText = $parts[0]
    $prefixLength = if ($parts.Count -eq 2) { $parts[1] } else { $null }

    if ($addressText -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        throw "Invalid IPv4 address or CIDR '$Value'. Use values such as 203.0.113.10 or 203.0.113.10/32."
    }
    foreach ($octet in ($addressText -split '\.')) {
        if ([int]$octet -lt 0 -or [int]$octet -gt 255) {
            throw "Invalid IPv4 address or CIDR '$Value'. Each octet must be 0-255."
        }
    }
    if ($null -eq $prefixLength) {
        return $addressText
    }
    if ($prefixLength -notmatch '^\d{1,2}$' -or [int]$prefixLength -lt 0 -or [int]$prefixLength -gt 32) {
        throw "Invalid CIDR prefix '$prefixLength'. IPv4 prefixes must be 0-32."
    }

    return "$addressText/$([int]$prefixLength)"
}

function Get-PublicIpAddress {
    foreach ($service in @('https://api.ipify.org', 'https://checkip.amazonaws.com', 'https://ifconfig.me/ip')) {
        try {
            $ipAddress = (Invoke-RestMethod -Uri $service -TimeoutSec 8 -ErrorAction Stop).Trim()
            if ($ipAddress -match '^\d{1,3}(\.\d{1,3}){3}$') {
                return $ipAddress
            }
        } catch { }
    }

    return $null
}

function Add-UniqueCidr {
    param(
        [AllowEmptyCollection()]
        [Parameter(Mandatory)] [System.Collections.Generic.List[string]] $Cidrs,
        [Parameter(Mandatory)] [string] $Value
    )

    $cidr = Convert-ToIpv4SourceAddress -Value $Value
    if (-not $Cidrs.Contains($cidr)) {
        $Cidrs.Add($cidr)
    }
}

Write-Info ''
Write-Task 'Add RDP allow rules to jumpbox NSG'
Write-Info "  Environment: $EnvironmentSuffix"
if ($WhatIf) { Write-Info '  Mode: WhatIf (display only, no Azure changes)' }
Write-Info ''

az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Info '  No active Azure session - running az login...'
    az login
}

$subscriptionId = az account show --query id --output tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionId)) {
    Write-Error 'Unable to determine the active Azure subscription.'
    exit 1
}

$nameSuffix = ($subscriptionId.Trim() -replace '-', '').Substring(0, 4).ToLower()
$config = Read-EnterpriseEnvironmentConfig -ScriptRoot $scriptRoot -EnvironmentSuffix $EnvironmentSuffix -NameSuffix $nameSuffix

if (-not (Convert-ToBoolean -Value $config.deployVm -Default $true)) {
    Write-Error "deployVm is false for '$EnvironmentSuffix'; no jumpbox NSG is expected."
    exit 1
}

$userCidrs = [System.Collections.Generic.List[string]]::new()
foreach ($configuredCidr in @($config.rdpAllowedIpCidrs)) {
    if ([string]::IsNullOrWhiteSpace([string]$configuredCidr)) { continue }
    Add-UniqueCidr -Cidrs $userCidrs -Value ([string]$configuredCidr)
}
$deployerCidrs = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($IpAddress)) {
    Add-UniqueCidr -Cidrs $deployerCidrs -Value $IpAddress
}
if (-not [string]::IsNullOrWhiteSpace($IpCidr)) {
    Add-UniqueCidr -Cidrs $deployerCidrs -Value $IpCidr
}
if ($UseCurrentPublicIp) {
    Write-Task 'Detecting current public IP address...'
    $currentPublicIp = Get-PublicIpAddress
    if ([string]::IsNullOrWhiteSpace($currentPublicIp)) {
        Write-Error 'Could not determine the current public IP address.'
        exit 1
    }
    Add-UniqueCidr -Cidrs $deployerCidrs -Value $currentPublicIp
    Write-Info "  Public IP detected: $currentPublicIp"
}

if ($userCidrs.Count -eq 0 -and $deployerCidrs.Count -eq 0) {
    Write-Error 'No RDP CIDRs were supplied. Add rdpAllowedPublicIpAddress or rdpAllowedIpCidrs to your environment YAML, or pass -IpAddress, -IpCidr, or -UseCurrentPublicIp.'
    exit 1
}

$networkResourceGroupName = $config.networkResourceGroupName
$nsgName = "$($config.vmName)-nsg"

Write-Task "Checking NSG '$nsgName' in '$networkResourceGroupName'..."
$nsgId = az network nsg show `
    --resource-group $networkResourceGroupName `
    --name $nsgName `
    --query id `
    --output tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($nsgId)) {
    Write-Error "NSG '$nsgName' was not found in resource group '$networkResourceGroupName'. Deploy the VM networking first."
    exit 1
}
Write-Exists '  NSG found.'

Write-Task 'Ensuring deny-all RDP rule remains present...'
$denyRuleName = 'deny-rdp-all'
$denyRuleExists = az network nsg rule show `
    --resource-group $networkResourceGroupName `
    --nsg-name $nsgName `
    --name $denyRuleName `
    --query name `
    --output tsv 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($denyRuleExists)) {
    Write-Exists '  deny-rdp-all already exists.'
} elseif ($WhatIf) {
    Write-Info '  Would create deny-rdp-all at priority 4096.'
} else {
    az network nsg rule create `
        --resource-group $networkResourceGroupName `
        --nsg-name $nsgName `
        --name $denyRuleName `
        --priority 4096 `
        --direction Inbound `
        --access Deny `
        --protocol Tcp `
        --source-address-prefixes '*' `
        --source-port-ranges '*' `
        --destination-address-prefixes '*' `
        --destination-port-ranges 3389 `
        --description 'Deny RDP from all sources unless an earlier allow rule matches.' `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Failed to create deny-rdp-all rule.'
        exit 1
    }
    Write-Exists '  deny-rdp-all created.'
}

$legacyRuleNames = @(az network nsg rule list `
    --resource-group $networkResourceGroupName `
    --nsg-name $nsgName `
    --query "[?starts_with(name, 'allow-rdp-from-')].name" `
    --output tsv 2>$null)
foreach ($legacyRuleName in $legacyRuleNames) {
    if ([string]::IsNullOrWhiteSpace($legacyRuleName)) { continue }
    if ($WhatIf) {
        Write-Info "  Would remove legacy rule '$legacyRuleName'."
        continue
    }
    az network nsg rule delete --resource-group $networkResourceGroupName --nsg-name $nsgName --name $legacyRuleName --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to remove legacy NSG rule '$legacyRuleName'."
        exit 1
    }
    Write-Exists "  Removed legacy rule '$legacyRuleName'."
}

$rules = @(
    @{ Name = 'allow-rdp-user'; Priority = 200; Sources = @($userCidrs); Description = 'Allow RDP from environment-configured user addresses.' }
    @{ Name = 'allow-rdp-deployer'; Priority = 201; Sources = @($deployerCidrs); Description = 'Allow temporary RDP access from the deploying or connecting machine.' }
)
foreach ($rule in $rules) {
    if ($rule.Sources.Count -eq 0) { continue }
    Write-Task "Configuring RDP allow rule '$($rule.Name)'..."
    if ($WhatIf) {
        Write-Info "  Would create or update priority $($rule.Priority) for: $($rule.Sources -join ', ')"
        continue
    }

    $existingRule = az network nsg rule show --resource-group $networkResourceGroupName --nsg-name $nsgName --name $rule.Name --query name --output tsv 2>$null
    $operation = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($existingRule)) { 'update' } else { 'create' }
    $arguments = @(
        'network', 'nsg', 'rule', $operation,
        '--resource-group', $networkResourceGroupName,
        '--nsg-name', $nsgName,
        '--name', $rule.Name,
        '--priority', $rule.Priority,
        '--direction', 'Inbound',
        '--access', 'Allow',
        '--protocol', 'Tcp',
        '--source-address-prefixes'
    ) + @($rule.Sources) + @(
        '--source-port-ranges', '*',
        '--destination-address-prefixes', '*',
        '--destination-port-ranges', '3389',
        '--description', $rule.Description,
        '--output', 'none'
    )
    & az @arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to configure NSG rule '$($rule.Name)'."
        exit 1
    }
    Write-Exists "  Rule '$($rule.Name)' allows RDP from '$($rule.Sources -join ', ')'."
}

Write-Exists 'RDP allow rule update completed.'
Write-ScriptTimingSummary -Status 'completed'