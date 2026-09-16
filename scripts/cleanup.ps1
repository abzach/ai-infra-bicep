# cleanup.ps1 — Deletes all resource groups for the specified environment.
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

Write-Task "Resource groups targeted for deletion:"
foreach ($rgName in $resourceGroups) {
    if ($existingResourceGroups.Contains($rgName)) {
        Write-Needed "  $rgName"
    } else {
        Write-Info "  $rgName (not found - already gone)"
    }
}
Write-Info ''

Write-Needed 'This permanently deletes all resources in both resource groups.'
Write-Info   'Soft-delete purging (Key Vault, OpenAI) is handled by deploy.ps1 on next run.'
Write-Info ''

if ($WhatIf) {
    Write-Exists "WhatIf: no changes made."
    Complete-ScriptLogging -Status 'completed (WhatIf)'
    exit 0
}

if ($existingResourceGroups.Count -eq 0) {
    Write-Exists 'Nothing to delete - all matching resource groups are already gone.'
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

$rgsToDelete = @()
foreach ($rg in $resourceGroups) {
    if ((az group exists --name $rg) -eq 'true') {
        Remove-ResourceGroupLocks -ResourceGroupName $rg
        Write-Task "Initiating deletion of '$rg'..."
        az group delete --name $rg --yes --no-wait 2>&1 | Out-Null
        $rgsToDelete += $rg
    }
}

Write-Info ''

foreach ($rg in $rgsToDelete) {
    Write-Task "Waiting for '$rg' to be fully deleted (timeout 10 min)..."
    $removed = Wait-WithBackoff -Condition {
        return (az group exists --name $rg) -ne 'true'
    } -MaxWaitSeconds 600 -InitialDelaySeconds 5 -MaxDelaySeconds 60 -OperationName "RG deletion"

    if ($removed) {
        Write-Exists "  '$rg' deleted."
    } else {
        Write-Needed "  Warning: '$rg' deletion timed out — may still be running in background."
        Write-Info   "  Try checking with: az group exists --name $rg"
    }
}

Write-Info ''
Write-Exists "Cleanup complete for '$EnvironmentSuffix'."
Write-Info ''
Complete-ScriptLogging -Status 'completed'
