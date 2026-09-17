# cleanup.ps1 — Deletes environment resources except Key Vault and the VM OS disk.
#
# EXAMPLES
#   # Preview what would be deleted
#   .\cleanup.ps1 -EnvironmentSuffix dev -WhatIf
#
#   # Interactive confirmation prompt
#   .\cleanup.ps1 -EnvironmentSuffix dev
#
#   # Non-interactive (pipeline / CI)
#   .\cleanup.ps1 -EnvironmentSuffix dev -Force

param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'uat')]
    [string] $EnvironmentSuffix,

    [switch] $WhatIf,

    [switch] $Force
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

    throw 'Unable to resolve the script root for cleanup.ps1.'
}

$scriptRoot = Get-CurrentScriptRoot

. (Join-Path $scriptRoot 'config.ps1')
. (Join-Path $scriptRoot 'common.ps1')

Initialize-ScriptLogging -ScriptRoot $scriptRoot -ScriptName 'cleanup.ps1'
trap { Write-LogEntry -Level 'ERROR' -Message "Unhandled error: $($_.Exception.Message)"; Write-ScriptTimingSummary -Status 'failed' }

function Add-UniqueResourceGroupName {
    param(
        [AllowEmptyCollection()]
        [Parameter(Mandatory)] [System.Collections.Generic.List[string]] $Names,
        [Parameter(Mandatory)] [string] $Name
    )

    if (-not [string]::IsNullOrWhiteSpace($Name) -and -not $Names.Contains($Name)) {
        $Names.Add($Name)
    }
}

Write-Info ''
Write-Task "Enterprise resource cleanup"
Write-Info "  Environment: $EnvironmentSuffix"
if ($WhatIf) { Write-Info "  Mode: WhatIf (display only, no deletion)" }
if ($Force) { Write-Info "  Confirmation: Force (non-interactive)" }
Write-Info ''

az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Info "  No active Azure session - running az login..."
    az login
}

$subscriptionId = az account show --query id --output tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionId)) {
    Write-Error 'Unable to determine the active Azure subscription.'
    exit 1
}

$nameSuffix = ($subscriptionId.Trim() -replace '-', '').Substring(0, 4).ToLower()
$configWithSuffix = Read-EnterpriseEnvironmentConfig -ScriptRoot $scriptRoot -EnvironmentSuffix $EnvironmentSuffix -NameSuffix $nameSuffix
$coreRg    = $configWithSuffix.coreResourceGroupName
$networkRg = $configWithSuffix.networkResourceGroupName
$legacyConfig = Read-EnterpriseEnvironmentConfig -ScriptRoot $scriptRoot -EnvironmentSuffix $EnvironmentSuffix
$expectedWorkloadTag = if ([string]::IsNullOrWhiteSpace($configWithSuffix.tagWorkload)) { 'enterprise-ai-foundry' } else { $configWithSuffix.tagWorkload }

$resourceGroups = [System.Collections.Generic.List[string]]::new()
Add-UniqueResourceGroupName -Names $resourceGroups -Name $coreRg
Add-UniqueResourceGroupName -Names $resourceGroups -Name $networkRg
Add-UniqueResourceGroupName -Names $resourceGroups -Name $legacyConfig.coreResourceGroupName
Add-UniqueResourceGroupName -Names $resourceGroups -Name $legacyConfig.networkResourceGroupName

Write-Task "Configuration loaded from variables/$EnvironmentSuffix.yaml"
Write-Info "  Subscription suffix : $nameSuffix"
Write-Info "  Current core RG     : $coreRg"
Write-Info "  Current network RG  : $networkRg"
Write-Info "  Legacy core RG      : $($legacyConfig.coreResourceGroupName)"
Write-Info "  Legacy network RG   : $($legacyConfig.networkResourceGroupName)"
Write-Info "  Expected workload tag: $expectedWorkloadTag"
Write-Info ''

$existingResourceGroups = [System.Collections.Generic.List[string]]::new()
foreach ($rgName in $resourceGroups) {
    $rgExists = (az group exists --name $rgName) -eq 'true'
    if (-not $rgExists) { continue }

    Add-UniqueResourceGroupName -Names $existingResourceGroups -Name $rgName

    $rgWorkloadTag = (az group show --name $rgName --query "tags.workload" --output tsv 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rgWorkloadTag)) {
        Write-Error "Resource group '$rgName' has no 'workload' tag. Aborting cleanup to prevent accidental deletion of unrelated resources."
        exit 1
    }
    if ($rgWorkloadTag.Trim() -ne $expectedWorkloadTag) {
        Write-Error "Resource group '$rgName' workload tag '$($rgWorkloadTag.Trim())' does not match expected '$expectedWorkloadTag'. Aborting cleanup."
        exit 1
    }
}

Write-Exists "  Tag guard passed: all existing resource groups have workload='$expectedWorkloadTag'."
Write-Info ''

$protectedKeyVaultNames = @($configWithSuffix.keyVaultName, $legacyConfig.keyVaultName) | Sort-Object -Unique
$protectedDiskNames = @("$($configWithSuffix.vmName)-osdisk", "$($legacyConfig.vmName)-osdisk") | Sort-Object -Unique
$projectNames = @($configWithSuffix.projectName, $legacyConfig.projectName) | Sort-Object -Unique
$resourcesToDelete = [System.Collections.Generic.List[object]]::new()
$resourcesToPreserve = [System.Collections.Generic.List[object]]::new()

foreach ($rgName in $existingResourceGroups) {
    $resourceJson = az resource list --resource-group $rgName --output json 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Unable to enumerate resources in '$rgName'."
        exit 1
    }

    foreach ($resource in @($resourceJson | ConvertFrom-Json)) {
        $isProtectedKeyVault = $resource.type -eq 'Microsoft.KeyVault/vaults' -and $resource.name -in $protectedKeyVaultNames
        $isProtectedDisk = $resource.type -eq 'Microsoft.Compute/disks' -and $resource.name -in $protectedDiskNames
        if ($isProtectedKeyVault -or $isProtectedDisk) {
            $resourcesToPreserve.Add($resource)
        } else {
            $resourcesToDelete.Add($resource)
        }
    }
}

Write-Task 'Resources preserved:'
foreach ($resource in $resourcesToPreserve) {
    Write-Exists "  $($resource.type)/$($resource.name)"
}
if ($resourcesToPreserve.Count -eq 0) {
    Write-Info '  No protected Key Vault or OS disk currently exists.'
}
Write-Info ''

Write-Task 'Resources targeted for deletion:'
foreach ($resource in $resourcesToDelete) {
    Write-Needed "  $($resource.type)/$($resource.name)"
}
if ($resourcesToDelete.Count -eq 0) {
    Write-Info '  No deletable resources found.'
}
Write-Info ''

Write-Needed 'This permanently deletes every listed resource while retaining the Key Vault, VM OS disk, and resource-group containers.'
Write-Info ''

if ($WhatIf) {
    Write-Exists "WhatIf: no changes made."
    Complete-ScriptLogging -Status 'completed (WhatIf)'
    exit 0
}

if ($resourcesToDelete.Count -eq 0) {
    Write-Exists 'Nothing to delete - only protected resources remain.'
    Complete-ScriptLogging -Status 'completed (nothing to delete)'
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host "Type 'yes' to proceed with cleanup"
    if ($confirm -ne 'yes') {
        Write-Task "Cleanup cancelled."
        Complete-ScriptLogging -Status 'cancelled'
        exit 0
    }
} else {
    Write-Task 'Force specified - proceeding without interactive confirmation.'
}

Write-Info ''

$deletePriority = @{
    'Microsoft.DevTestLab/schedules' = 10
    'Microsoft.Compute/virtualMachines' = 20
    'Microsoft.Automation/automationAccounts' = 30
    'Microsoft.MachineLearningServices/workspaces' = 40
    'Microsoft.Network/privateEndpoints' = 50
    'Microsoft.Network/networkInterfaces' = 60
    'Microsoft.Storage/storageAccounts' = 70
    'Microsoft.CognitiveServices/accounts' = 80
    'Microsoft.OperationalInsights/workspaces' = 90
    'Microsoft.ManagedIdentity/userAssignedIdentities' = 100
    'Microsoft.Network/publicIPAddresses' = 110
    'Microsoft.Network/networkSecurityGroups' = 120
    'Microsoft.Network/privateDnsZones' = 130
    'Microsoft.Network/virtualNetworks' = 140
}

$orderedResources = @($resourcesToDelete | Sort-Object @{
    Expression = {
        if ([string]$_.type -eq 'Microsoft.MachineLearningServices/workspaces' -and [string]$_.name -in $projectNames) { 35 }
        elseif ($deletePriority.ContainsKey([string]$_.type)) { $deletePriority[[string]$_.type] }
        else { 75 }
    }
}, @{ Expression = { [string]$_.id } })

foreach ($resource in $orderedResources) {
    Write-Task "Deleting $($resource.type)/$($resource.name)..."
    if ($resource.type -eq 'Microsoft.Compute/virtualMachines') {
        az vm update --ids $resource.id --set storageProfile.osDisk.deleteOption=Detach --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to set the OS disk delete option to Detach for '$($resource.name)'."
            exit 1
        }
        az vm delete --ids $resource.id --yes --output none
    } else {
        az resource delete --ids $resource.id --output none
    }

    if ($LASTEXITCODE -ne 0) {
        az resource show --ids $resource.id --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Error "Failed to delete '$($resource.id)'. Resolve the dependency or lock and rerun cleanup."
            exit 1
        }
    }
    Write-Exists "  Deleted $($resource.type)/$($resource.name)."
}

Write-Info ''
Write-Exists "Cleanup complete for '$EnvironmentSuffix'. Key Vault and VM OS disk were preserved."
Write-Info ''
Complete-ScriptLogging -Status 'completed'
