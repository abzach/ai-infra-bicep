# main.ps1 — Root dispatcher for common environment operations.
#
# EXAMPLES
#   .\main.ps1 dev-connect
#   .\main.ps1 dev-deploy
#   .\main.ps1 dev-clean

param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('dev-connect', 'dev-deploy', 'dev-clean', 'uat-connect', 'uat-deploy', 'uat-clean')]
    [string] $Target,

    [string] $VmAdminPassword,

    [string] $IpAddress,

    [string] $IpCidr,

    [switch] $UseCurrentPublicIp,

    [switch] $RotateVmPassword,

    [switch] $SkipRoleElevation,

    [switch] $ForceAppBootstrap,

    [switch] $ForceRedeploy,

    [switch] $Force,

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

    throw 'Unable to resolve the repository root for main.ps1.'
}

$repoRoot = Get-CurrentScriptRoot
$scriptRoot = Join-Path $repoRoot 'scripts'
$environmentSuffix = ($Target -split '-', 2)[0]
$operation = ($Target -split '-', 2)[1]

switch ($operation) {
    'connect' {
        $scriptPath = Join-Path $scriptRoot 'rdp.ps1'
        Write-Host "Preparing RDP access for '$environmentSuffix'. Deployment will not run."
        $scriptArguments = @{
            EnvironmentSuffix = $environmentSuffix
        }
        if (-not [string]::IsNullOrWhiteSpace($IpAddress)) { $scriptArguments['IpAddress'] = $IpAddress }
        if (-not [string]::IsNullOrWhiteSpace($IpCidr)) { $scriptArguments['IpCidr'] = $IpCidr }
        if ($UseCurrentPublicIp -or ([string]::IsNullOrWhiteSpace($IpAddress) -and [string]::IsNullOrWhiteSpace($IpCidr))) {
            $scriptArguments['UseCurrentPublicIp'] = $true
        }
        if ($WhatIf) { $scriptArguments['WhatIf'] = $true }

        & $scriptPath @scriptArguments
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        if (-not $WhatIf) {
            & (Join-Path $scriptRoot 'show.ps1') -EnvironmentSuffix $environmentSuffix
        }
        break
    }
    'deploy' {
        $scriptPath = Join-Path $scriptRoot 'deploy.ps1'
        Write-Host "Deploying '$environmentSuffix' environment."
        $scriptArguments = @{
            EnvironmentSuffix = $environmentSuffix
        }
        if (-not [string]::IsNullOrWhiteSpace($VmAdminPassword)) { $scriptArguments['VmAdminPassword'] = $VmAdminPassword }
        if ($RotateVmPassword) { $scriptArguments['RotateVmPassword'] = $true }
        if ($SkipRoleElevation) { $scriptArguments['SkipRoleElevation'] = $true }
        if ($ForceAppBootstrap) { $scriptArguments['ForceAppBootstrap'] = $true }
        if ($ForceRedeploy) { $scriptArguments['ForceRedeploy'] = $true }
        if ($WhatIf) { $scriptArguments['WhatIf'] = $true }

        & $scriptPath @scriptArguments
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        if (-not $WhatIf) {
            . (Join-Path $scriptRoot 'config.ps1')
            $postDeployConfig = Read-EnterpriseEnvironmentConfig -ScriptRoot $scriptRoot -EnvironmentSuffix $environmentSuffix
            if ([string]$postDeployConfig.deployVm -eq 'true') {
                & (Join-Path $scriptRoot 'rdp.ps1') -EnvironmentSuffix $environmentSuffix -UseCurrentPublicIp
            }
        }
        break
    }
    'clean' {
        $scriptPath = Join-Path $scriptRoot 'cleanup.ps1'
        Write-Host "Cleaning '$environmentSuffix' environment while preserving Key Vault and the VM OS disk."
        $scriptArguments = @{
            EnvironmentSuffix = $environmentSuffix
        }
        if ($Force) { $scriptArguments['Force'] = $true }
        if ($WhatIf) { $scriptArguments['WhatIf'] = $true }

        & $scriptPath @scriptArguments
        break
    }
}