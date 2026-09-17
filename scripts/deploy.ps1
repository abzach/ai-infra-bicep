# deploy.ps1 — Main infrastructure deployment orchestrator.
#
# EXAMPLES
#   # Full dev deploy
#   .\deploy.ps1 -EnvironmentSuffix dev
#
#   # Preview changes without deploying
#   .\deploy.ps1 -EnvironmentSuffix dev -WhatIf
#
#   # Deploy with a specific VM password (also stores it in Key Vault)
#   .\deploy.ps1 -EnvironmentSuffix dev -VmAdminPassword 'MyP@ss123!'
#
#   # Force a deployment even when the existing environment is already current
#   .\deploy.ps1 -EnvironmentSuffix dev -ForceRedeploy
#
#   # Rotate the jumpbox password (reruns otherwise keep the existing password)
#   .\deploy.ps1 -EnvironmentSuffix dev -RotateVmPassword
#
# PREREQUISITES
#   - Azure CLI installed and `az login` completed. The script preflights and, when possible,
#     self-grants 'User Access Administrator' at subscription scope (see
#     .github/instructions/azure-rbac-preflight.instructions.md).
#   - PowerShell 7+ recommended
#   - config.ps1 and common.ps1 must be present in the same directory

param(
    [Parameter(Mandatory)] [ValidateSet('dev','uat')] [string] $EnvironmentSuffix,
    [ValidateSet('deploy','myip')] [string] $Action = 'deploy',
    [string] $VmAdminPassword,
    [switch] $RotateVmPassword,
    [switch] $SkipRoleElevation,
    [switch] $ForceAppBootstrap,
    [switch] $ForceRedeploy,
    [switch] $WhatIf
)


Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$isCi = $env:CI -eq 'true' -or $env:GITHUB_ACTIONS -eq 'true' -or $env:TF_BUILD -eq 'True'

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

    throw 'Unable to resolve the script root for deploy.ps1.'
}

$scriptRoot = Get-CurrentScriptRoot

. (Join-Path $scriptRoot 'config.ps1')
. (Join-Path $scriptRoot 'common.ps1')

Initialize-ScriptLogging -ScriptRoot $scriptRoot -ScriptName 'deploy.ps1'
trap { Write-LogEntry -Level 'ERROR' -Message "Unhandled error: $($_.Exception.Message)"; Write-ScriptTimingSummary -Status 'failed' }

Update-BicepCli

function Convert-ToBoolean {
    param(
        [Parameter(Mandatory)] [object] $Value,
        [bool] $Default = $false
    )

    if ($null -eq $Value) {
        return $Default
    }

    $text = $Value.ToString().Trim().ToLower()
    if ($text -in @('true', '1', 'yes', 'y')) {
        return $true
    }
    if ($text -in @('false', '0', 'no', 'n')) {
        return $false
    }

    return $Default
}

function Show-AzureContext {
    $accountJson = az account show --output json
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accountJson)) {
        Write-Error 'Unable to read Azure account context from Azure CLI.'
        exit 1
    }

    $account = $accountJson | ConvertFrom-Json
    $userName = if ($account.user -and $account.user.name) { $account.user.name } else { '<unknown>' }
    $userType = if ($account.user -and $account.user.type) { $account.user.type } else { '<unknown>' }

    Write-Task 'Azure context detected:'
    Write-Info "  Account       : $userName ($userType)"
    Write-Info "  Subscription  : $($account.name)"
    Write-Info "  SubscriptionId: $($account.id)"
    Write-Info "  TenantId      : $($account.tenantId)"
}

function Get-AzureArmAccessToken {
    param(
        [Parameter(Mandatory)] [string] $SubscriptionId
    )

    $accessToken = az account get-access-token `
        --subscription $SubscriptionId `
        --resource-type arm `
        --query accessToken `
        --output tsv 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accessToken)) {
        return $null
    }

    return $accessToken.Trim()
}

function Get-AzureArmHeaders {
    param(
        [Parameter(Mandatory)] [string] $SubscriptionId
    )

    $accessToken = Get-AzureArmAccessToken -SubscriptionId $SubscriptionId
    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        return $null
    }

    return @{ Authorization = "Bearer $accessToken" }
}

function Get-SubscriptionDeploymentOutputs {
    param(
        [Parameter(Mandatory)] [string] $SubscriptionId,
        [Parameter(Mandatory)] [string] $DeploymentName,
        [int] $MaxAttempts = 3,
        [int] $DelaySeconds = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $deploymentOutputsJson = az deployment sub show `
            --name $DeploymentName `
            --subscription $SubscriptionId `
            --query properties.outputs `
            --output json 2>$null

        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($deploymentOutputsJson)) {
            try {
                return ($deploymentOutputsJson | ConvertFrom-Json)
            } catch {
                Write-Info 'Warning: could not parse deployment outputs JSON.'
                return $null
            }
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Info "Warning: could not read deployment outputs (attempt $attempt/$MaxAttempts). Retrying in $DelaySeconds seconds..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return $null
}

function Set-LogAnalyticsDailyQuota {
    param(
        [Parameter(Mandatory)] [string] $ResourceGroupName,
        [Parameter(Mandatory)] [string] $WorkspaceName,
        [Parameter(Mandatory)] [string] $DailyQuotaGb
    )

    if ([string]::IsNullOrWhiteSpace($DailyQuotaGb)) {
        return
    }

    Write-Task "Configuring Log Analytics daily ingestion cap to ${DailyQuotaGb}GB..."
    try {
        az monitor log-analytics workspace update `
            --resource-group $ResourceGroupName `
            --workspace-name $WorkspaceName `
            --quota $DailyQuotaGb `
            --output none 2>$null

        if ($LASTEXITCODE -eq 0) {
            Write-Exists '  Log Analytics daily cap configured.'
        } else {
            Write-Info '  Warning: unable to set Log Analytics daily cap (non-fatal).'
        }
    } catch {
        Write-Info "  Warning: Log Analytics daily cap could not be configured: $_"
    }
}

function Set-AuditDiagnosticsForResource {
    param(
        [Parameter(Mandatory)] [string] $ResourceId,
        [Parameter(Mandatory)] [string] $WorkspaceId
    )

    if ($ResourceId -match '/providers/Microsoft.Storage/storageAccounts/' -or
        $ResourceId -match '/providers/Microsoft.MachineLearningServices/workspaces/') {
        return
    }

    # Inspect existing diagnostic settings
    $existingDiagJson = az monitor diagnostic-settings list `
        --resource $ResourceId `
        --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($existingDiagJson)) {
        $existingDiags = ($existingDiagJson | ConvertFrom-Json)
        $diagList = if ($existingDiags.PSObject.Properties['value']) { $existingDiags.value } else { $existingDiags }
        foreach ($diag in $diagList) {
            # Remove settings that stream to a storage account
            if ($diag.PSObject.Properties['storageAccountId'] -and -not [string]::IsNullOrWhiteSpace($diag.storageAccountId)) {
                Write-Needed "  Removing diagnostic setting '$($diag.name)' on '$ResourceId' (streams to storage account)."
                az monitor diagnostic-settings delete `
                    --name $diag.name `
                    --resource $ResourceId `
                    --output none 2>$null
                continue
            }
            # If an existing setting already streams to the same LAW workspace, treat as already configured
            $settingWorkspaceId = if ($diag.PSObject.Properties['workspaceId']) { $diag.workspaceId } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($settingWorkspaceId) -and
                $settingWorkspaceId.ToLower() -eq $WorkspaceId.ToLower()) {
                Write-Exists "  Audit diagnostics already configured for '$ResourceId' (setting: '$($diag.name)')."
                return
            }
            # Delete a stale setting with the same target name before re-creating
            if ($diag.name -eq 'send-audit-to-law') {
                Write-Needed "  Removing stale diagnostic setting '$($diag.name)' on '$ResourceId'."
                az monitor diagnostic-settings delete `
                    --name $diag.name `
                    --resource $ResourceId `
                    --output none 2>$null
            }
        }
    }

    $categoriesJson = az monitor diagnostic-settings categories list `
        --resource $ResourceId `
        --output json 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($categoriesJson)) {
        Write-Info "  Skipping diagnostics for '$ResourceId' (categories unavailable)."
        return
    }

    $categories = $categoriesJson | ConvertFrom-Json
    $categoryList = if ($categories.PSObject.Properties['value']) { $categories.value } else { $categories }
    
    $auditLogCategories = @(
        $categoryList | Where-Object {
            $_.categoryType -eq 'Logs' -and ($_.name -match 'audit' -or $_.name -match 'ComputeInstanceEvent')
        } | ForEach-Object {
            @{
                category = $_.name
                enabled = $true
                retentionPolicy = @{ enabled = $false; days = 0 }
            }
        }
    )

    if ($auditLogCategories.Count -eq 0) {
        return
    }

    $diagName = 'send-audit-to-law'
    $logsTempFile = [System.IO.Path]::GetTempFileName()
    try {
        $logsJson = $auditLogCategories | ConvertTo-Json -Compress -Depth 10
        if (-not $logsJson.Trim().StartsWith('[')) {
            $logsJson = "[$logsJson]"
        }
        
        [System.IO.File]::WriteAllText($logsTempFile, $logsJson, [System.Text.UTF8Encoding]::new($false))

        $azOutput = az monitor diagnostic-settings create `
            --name $diagName `
            --resource $ResourceId `
            --workspace $WorkspaceId `
            --logs "@$logsTempFile" `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Exists "  Audit diagnostics enabled for '$ResourceId'."
        } else {
            Write-Info "  Warning: failed to configure diagnostics for '$ResourceId' (non-fatal)."
            Write-Info "  Error details: $azOutput"
            if (Test-Path $logsTempFile) {
                Write-Info "  Debug: Payload was $(Get-Content $logsTempFile)"
            }
        }
    } finally {
        Remove-Item $logsTempFile -Force -ErrorAction SilentlyContinue
    }
}

function Set-AuditDiagnosticsForImportantResources {
    param(
        [Parameter(Mandatory)] [string] $CoreResourceGroupName,
        [Parameter(Mandatory)] [string] $NetworkResourceGroupName,
        [Parameter(Mandatory)] [string] $WorkspaceId
    )

    Write-Task 'Configuring audit diagnostics for important resources...'

    $importantTypes = @(
        'Microsoft.CognitiveServices/accounts'
    )

    $resourcesJson = az resource list `
        --resource-group $CoreResourceGroupName `
        --output json 2>$null

    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($resourcesJson)) {
        $coreResources = $resourcesJson | ConvertFrom-Json
        foreach ($resource in $coreResources) {
            if ($resource.type -in $importantTypes) {
                Set-AuditDiagnosticsForResource -ResourceId $resource.id -WorkspaceId $WorkspaceId
            }
        }
    }

    $networkResourcesJson = az resource list `
        --resource-group $NetworkResourceGroupName `
        --output json 2>$null

    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($networkResourcesJson)) {
        $networkResources = $networkResourcesJson | ConvertFrom-Json
        foreach ($resource in $networkResources) {
            if ($resource.type -in $importantTypes) {
                Set-AuditDiagnosticsForResource -ResourceId $resource.id -WorkspaceId $WorkspaceId
            }
        }
    }
}

function New-SecurePassword {
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $lower = 'abcdefghijkmnopqrstuvwxyz'.ToCharArray()
    $digits = '23456789'.ToCharArray()
    $special = '!@$%*+-_?'.ToCharArray()
    $all = $upper + $lower + $digits + $special

    $passwordChars = @(
        Get-Random -InputObject $upper
        Get-Random -InputObject $lower
        Get-Random -InputObject $digits
        Get-Random -InputObject $special
    )

    for ($index = $passwordChars.Count; $index -lt 24; $index++) {
        $passwordChars += Get-Random -InputObject $all
    }

    return (-join ($passwordChars | Sort-Object { Get-Random }))
}

function Get-PublicIpAddress {
    $services = @(
        'https://api.ipify.org',
        'https://checkip.amazonaws.com',
        'https://ifconfig.me/ip'
    )
    foreach ($service in $services) {
        try {
            $ip = (Invoke-RestMethod -Uri $service -TimeoutSec 8 -ErrorAction Stop).Trim()
            if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') {
                return $ip
            }
        } catch { }
    }
    return $null
}

function Invoke-AzCliWithRetry {
    param(
        [Parameter(Mandatory)] [scriptblock] $Command,
        [Parameter(Mandatory)] [string] $Operation,
        [int] $MaxAttempts = 3,
        [int] $DelaySeconds = 8
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $commandOutput = & $Command 2>&1
        $exitCode = $LASTEXITCODE
        $outputText = [string]($commandOutput -join [Environment]::NewLine)

        if ($exitCode -eq 0) {
            return @{
                Success = $true
                Output = $outputText
                ExitCode = $exitCode
            }
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Info "  Warning: failed to $Operation (attempt $attempt/$MaxAttempts). Retrying in $DelaySeconds seconds..."
            Start-Sleep -Seconds $DelaySeconds
        } else {
            return @{
                Success = $false
                Output = $outputText
                ExitCode = $exitCode
            }
        }
    }

    return @{
        Success = $false
        Output = ''
        ExitCode = -1
    }
}

function Get-KeyVaultSecretFingerprint {
    param(
        [Parameter(Mandatory)] [string] $SecretValue
    )

    $hash = [System.Security.Cryptography.SHA256]::HashData(
        [System.Text.Encoding]::UTF8.GetBytes($SecretValue)
    )
    return "application/vnd.ai-infra.secret;sha256=$(([System.Convert]::ToHexString($hash)).ToLowerInvariant())"
}

function Test-KeyVaultSecretValueCurrent {
    param(
        [Parameter(Mandatory)] [string] $VaultResourceId,
        [Parameter(Mandatory)] [string] $SecretName,
        [Parameter(Mandatory)] [string] $SecretValue
    )

    $escapedSecretName = [System.Uri]::EscapeDataString($SecretName)
    $secretUri = "https://management.azure.com${VaultResourceId}/secrets/${escapedSecretName}?api-version=2023-07-01"
    $existingFingerprint = az rest `
        --method get `
        --url $secretUri `
        --query properties.contentType `
        --output tsv 2>$null

    return $LASTEXITCODE -eq 0 -and
        -not [string]::IsNullOrWhiteSpace($existingFingerprint) -and
        $existingFingerprint.Trim() -eq (Get-KeyVaultSecretFingerprint -SecretValue $SecretValue)
}

function Sync-KeyVaultSecretValue {
    param(
        [Parameter(Mandatory)] [string] $VaultResourceId,
        [Parameter(Mandatory)] [string] $SecretName,
        [Parameter(Mandatory)] [string] $SecretValue,
        [int] $MaxAttempts = 3,
        [int] $DelaySeconds = 8
    )

    if ([string]::IsNullOrWhiteSpace($SecretValue)) {
        return $true
    }

    if (Test-KeyVaultSecretValueCurrent -VaultResourceId $VaultResourceId -SecretName $SecretName -SecretValue $SecretValue) {
        Write-Exists "  Secret '$SecretName' already current."
        return $true
    }

    $escapedSecretName = [System.Uri]::EscapeDataString($SecretName)
    $secretUri = "https://management.azure.com${VaultResourceId}/secrets/${escapedSecretName}?api-version=2023-07-01"
    $bodyFile = Join-Path ([System.IO.Path]::GetTempPath()) "kv-secret-$PID-$([guid]::NewGuid().ToString('N')).json"

    try {
        @{
            properties = @{
                value = $SecretValue
                contentType = (Get-KeyVaultSecretFingerprint -SecretValue $SecretValue)
            }
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $bodyFile -Encoding utf8NoBOM

        $updatedSecretResult = Invoke-AzCliWithRetry `
            -Operation "write secret '$SecretName' through Azure Resource Manager" `
            -MaxAttempts $MaxAttempts `
            -DelaySeconds $DelaySeconds `
            -Command {
                az rest `
                    --method put `
                    --url $secretUri `
                    --headers 'Content-Type=application/json' `
                    --body "@$bodyFile" `
                    --query id `
                    --output tsv
            }

        if ($updatedSecretResult.Success) {
            Write-Exists "  Updated secret '$SecretName' through Azure Resource Manager."
            return $true
        }

        Write-Info "  Warning: failed to update secret '$SecretName' through Azure Resource Manager."
        if (-not [string]::IsNullOrWhiteSpace($updatedSecretResult.Output)) {
            Write-Info "  Azure Resource Manager error details: $($updatedSecretResult.Output)"
        }
        return $false
    } finally {
        Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-VmBootstrapPackage {
    param(
        [Parameter(Mandatory)] [string] $ResourceGroupName,
        [Parameter(Mandatory)] [string] $VmName,
        [Parameter(Mandatory)] [string[]] $FilePaths,
        [string] $GuestTimeZone = 'UTC'
    )

    $packageRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ai-infra-bootstrap-$PID-$([guid]::NewGuid().ToString('N'))"
    $archivePath = "$packageRoot.zip"
    $bootstrapScriptPath = "$packageRoot.ps1"

    try {
        New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
        foreach ($filePath in $FilePaths) {
            if (-not (Test-Path -LiteralPath $filePath)) {
                throw "Bootstrap file not found: $filePath"
            }
            $sourceName = Split-Path $filePath -Leaf
            $destinationName = if ($sourceName -like 'first-run-*.ps1') { 'first-run.ps1' } else { $sourceName }
            Copy-Item -LiteralPath $filePath -Destination (Join-Path $packageRoot $destinationName) -Force
        }

        Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal -Force
        $archiveBase64 = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($archivePath))
        $bootstrapScript = @"
`$ErrorActionPreference = 'Stop'
`$archivePath = 'C:\Windows\Temp\ai-infra-bootstrap.zip'
`$extractPath = 'C:\Windows\Temp\ai-infra-bootstrap'
[System.IO.File]::WriteAllBytes(`$archivePath, [System.Convert]::FromBase64String('$archiveBase64'))
Remove-Item -LiteralPath `$extractPath -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath `$archivePath -DestinationPath `$extractPath -Force
`$env:VM_GUEST_TIMEZONE = '$GuestTimeZone'
& (Join-Path `$extractPath 'setup.ps1')
Write-Output 'AI_INFRA_BOOTSTRAP_SUCCEEDED'
"@
        Set-Content -LiteralPath $bootstrapScriptPath -Value $bootstrapScript -Encoding utf8NoBOM

        $bootstrapResult = Invoke-AzCliWithRetry `
            -Operation "bootstrap VM '$VmName' through Azure Run Command" `
            -MaxAttempts 3 `
            -DelaySeconds 30 `
            -Command {
                az vm run-command invoke `
                    --resource-group $ResourceGroupName `
                    --name $VmName `
                    --command-id RunPowerShellScript `
                    --scripts "@$bootstrapScriptPath" `
                    --query 'value[].message' `
                    --output tsv
            }

        if (-not $bootstrapResult.Success -or $bootstrapResult.Output -notmatch 'AI_INFRA_BOOTSTRAP_SUCCEEDED') {
            if (-not [string]::IsNullOrWhiteSpace($bootstrapResult.Output)) {
                Write-Info "  VM bootstrap details: $($bootstrapResult.Output)"
            }
            return $false
        }

        return $true
    } finally {
        Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $archivePath, $bootstrapScriptPath -Force -ErrorAction SilentlyContinue
    }
}

function Update-VmUserPassword {
    param(
        [Parameter(Mandatory)] [string] $ResourceGroupName,
        [Parameter(Mandatory)] [string] $VmName,
        [Parameter(Mandatory)] [string] $Username,
        [Parameter(Mandatory)] [string] $Password,
        [int] $MaxAttempts = 3,
        [int] $DelaySeconds = 15
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        az vm user update `
            --resource-group $ResourceGroupName `
            --name $VmName `
            --username $Username `
            --password $Password `
            --output none

        if ($LASTEXITCODE -eq 0) {
            return $true
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Info "  Attempt $attempt to reset VM password failed; retrying in $DelaySeconds seconds..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return $false
}

function Get-StoredVmCredentialPassword {
    param(
        [Parameter(Mandatory)] [string] $CredentialFilePath
    )

    if (-not (Test-Path -LiteralPath $CredentialFilePath -PathType Leaf)) {
        return ''
    }

    try {
        $passwordLine = Get-Content -LiteralPath $CredentialFilePath |
            Where-Object { $_ -match '^Password:\s*' } |
            Select-Object -First 1
    } catch {
        return ''
    }

    if ([string]::IsNullOrWhiteSpace($passwordLine)) {
        return ''
    }

    return ($passwordLine -replace '^Password:\s*', '').Trim()
}

# ---------------------------------------------------------------------------
# Test-ExistingVmRetainsPassword
#   Returns $true when the jumpbox already exists and this deployment will not
#   recreate it, meaning its current admin password must be preserved.
#   Returns $false when the VM is absent or will be deleted and recreated
#   because its Spot/Regular priority no longer matches the configuration, in
#   which case a fresh password has to be generated.
# ---------------------------------------------------------------------------
function Test-ExistingVmRetainsPassword {
    param(
        [Parameter(Mandatory)] [string] $ResourceGroupName,
        [Parameter(Mandatory)] [string] $VmName,
        [Parameter(Mandatory)] [bool] $UseSpot,
        [Parameter(Mandatory)] [bool] $VmDeploymentEnabled
    )

    if (-not $VmDeploymentEnabled) {
        return $true
    }

    $existingVmId = az vm show `
        --resource-group $ResourceGroupName `
        --name $VmName `
        --query id `
        --output tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($existingVmId)) {
        return $false
    }

    $existingPriority = az resource show `
        --resource-group $ResourceGroupName `
        --name $VmName `
        --resource-type 'Microsoft.Compute/virtualMachines' `
        --query 'properties.priority' `
        --output tsv 2>$null
    if ($LASTEXITCODE -ne 0) {
        # Priority is unreadable, so the later pre-deploy check will not delete the VM either.
        return $true
    }

    $existingIsSpot = ($existingPriority -eq 'Spot')
    return $existingIsSpot -eq $UseSpot
}

function Get-VmPowerState {
    param(
        [Parameter(Mandatory)] [string] $ResourceGroupName,
        [Parameter(Mandatory)] [string] $VmName
    )

    $state = az vm get-instance-view `
        --resource-group $ResourceGroupName `
        --name $VmName `
        --query "instanceView.statuses[?starts_with(code,'PowerState/')].code | [0]" `
        --output tsv 2>$null

    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($state)) {
        return $state.Trim()
    }

    return $null
}

function Ensure-VmRunning {
    param(
        [Parameter(Mandatory)] [string] $ResourceGroupName,
        [Parameter(Mandatory)] [string] $VmName,
        [int] $MaxStartAttempts = 3,
        [int] $StartDelaySeconds = 15,
        [int] $PollIntervalSeconds = 10,
        [int] $PollAttempts = 12
    )

    $powerState = Get-VmPowerState -ResourceGroupName $ResourceGroupName -VmName $VmName
    if ($powerState -eq 'PowerState/running') {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($powerState)) {
        Write-Info '  Unable to determine VM power state before attempting to start.'
    } else {
        Write-Info "  VM is currently $powerState; it must be running to reset credentials."
    }

    for ($attempt = 1; $attempt -le $MaxStartAttempts; $attempt++) {
        Write-Info "  Starting VM '$VmName' (attempt $attempt of $MaxStartAttempts)..."
        az vm start `
            --resource-group $ResourceGroupName `
            --name $VmName `
            --output none

        if ($LASTEXITCODE -ne 0) {
            Write-Info "  az vm start failed (exit code $LASTEXITCODE)."
            if ($attempt -lt $MaxStartAttempts) {
                Start-Sleep -Seconds $StartDelaySeconds
                continue
            }
            break
        }

        for ($poll = 1; $poll -le $PollAttempts; $poll++) {
            Start-Sleep -Seconds $PollIntervalSeconds
            $powerState = Get-VmPowerState -ResourceGroupName $ResourceGroupName -VmName $VmName
            if ($powerState -eq 'PowerState/running') {
                Write-Info '  VM is running.'
                return $true
            }
        }

        Write-Info "  VM did not report a running state after start attempt $attempt."
        if ($attempt -lt $MaxStartAttempts) {
            Start-Sleep -Seconds $StartDelaySeconds
        }
    }

    if ($powerState) {
        Write-Info "  VM is still in state '$powerState'."
    }

    return $false
}

function Get-DeploymentOutputValue {
    param(
        [AllowNull()] [object] $Outputs,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($null -eq $Outputs) { return '' }
    $prop = $Outputs.PSObject.Properties[$Name]
    if ($null -eq $prop) { return '' }
    $val = $prop.Value
    if ($null -eq $val) { return '' }
    if ($val.PSObject.Properties['value']) { return [string]$val.value }
    return [string]$val
}

function Get-DeploymentDesiredStateHash {
    param(
        [Parameter(Mandatory)] [string] $ScriptRoot,
        [Parameter(Mandatory)] [ValidateSet('dev','uat')] [string] $EnvironmentSuffix
    )

    $repoRoot = (Resolve-Path -Path (Join-Path $ScriptRoot '..') -ErrorAction Stop).Path
    $relativePaths = [System.Collections.Generic.List[string]]::new()
    $relativePaths.Add('bicep\templates\main.bicep')
    $relativePaths.Add('variables\core.yaml')
    $relativePaths.Add("variables\$EnvironmentSuffix.yaml")
    $relativePaths.Add('scripts\deploy.ps1')
    $relativePaths.Add('scripts\config.ps1')
    $relativePaths.Add('scripts\common.ps1')
    $relativePaths.Add('scripts\setup.ps1')
    $relativePaths.Add('main.ps1')
    $relativePaths.Add('scripts\add-rdp-allow-rule.ps1')
    $relativePaths.Add('scripts\show-vm-admin-password.ps1')
    $relativePaths.Add('app\chat.py')
    $relativePaths.Add('app\test.py')
    $relativePaths.Add('app\requirements.txt')

    $modulesPath = Join-Path $repoRoot 'bicep\modules'
    Get-ChildItem -Path $modulesPath -Filter '*.bicep' -File | Sort-Object Name | ForEach-Object {
        $relativePaths.Add([System.IO.Path]::GetRelativePath($repoRoot, $_.FullName))
    }

    $automationPath = Join-Path $repoRoot 'automation'
    if (Test-Path -LiteralPath $automationPath -PathType Container) {
        Get-ChildItem -Path $automationPath -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
            $relativePaths.Add([System.IO.Path]::GetRelativePath($repoRoot, $_.FullName))
        }
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($relativePath in ($relativePaths | Sort-Object -Unique)) {
            $fullPath = Join-Path $repoRoot $relativePath
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                throw "Desired-state input file not found: $fullPath"
            }

            $normalizedRelativePath = ([System.IO.Path]::GetRelativePath($repoRoot, (Resolve-Path -Path $fullPath).Path)).Replace('\', '/')
            $pathBytes = [System.Text.Encoding]::UTF8.GetBytes("$normalizedRelativePath`n")
            $null = $sha256.TransformBlock($pathBytes, 0, $pathBytes.Length, $null, 0)

            $fileBytes = [System.IO.File]::ReadAllBytes($fullPath)
            $null = $sha256.TransformBlock($fileBytes, 0, $fileBytes.Length, $null, 0)

            $separatorBytes = [System.Text.Encoding]::UTF8.GetBytes("`n")
            $null = $sha256.TransformBlock($separatorBytes, 0, $separatorBytes.Length, $null, 0)
        }

        $null = $sha256.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return ([System.BitConverter]::ToString($sha256.Hash) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Get-AutomationRunbookDescriptors {
    param(
        [Parameter(Mandatory)] [string] $ScriptRoot
    )

    $automationPath = Join-Path $ScriptRoot '..\automation'
    if (-not (Test-Path -LiteralPath $automationPath -PathType Container)) {
        throw "Automation source directory not found: $automationPath"
    }

    $scriptFiles = @(Get-ChildItem -LiteralPath $automationPath -Filter '*.ps1' -File | Sort-Object Name)
    if ($scriptFiles.Count -eq 0) {
        throw "Automation is enabled but no top-level PowerShell runbooks were found in '$automationPath'."
    }

    $seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $descriptors = [System.Collections.Generic.List[object]]::new()
    foreach ($scriptFile in $scriptFiles) {
        $runbookName = [System.IO.Path]::GetFileNameWithoutExtension($scriptFile.Name)
        if ($runbookName -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
            throw "Automation runbook filename '$($scriptFile.Name)' is invalid. Names must start with a letter and contain only letters, numbers, hyphens, and underscores."
        }
        if (-not $seenNames.Add($runbookName)) {
            throw "Automation runbook name '$runbookName' is duplicated without regard to case."
        }

        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            $messages = $parseErrors | ForEach-Object { "$($_.Extent.StartLineNumber):$($_.Message)" }
            throw "Automation runbook '$($scriptFile.Name)' has PowerShell parse errors: $($messages -join '; ')"
        }

        $descriptors.Add([pscustomobject]@{
            name = $runbookName
            sourceHash = (Get-FileHash -LiteralPath $scriptFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            path = $scriptFile.FullName
        })
    }

    return @($descriptors)
}

function Get-AutomationScheduleStartTime {
    param(
        [Parameter(Mandatory)] [string] $SubscriptionId,
        [Parameter(Mandatory)] [string] $ResourceGroupName,
        [Parameter(Mandatory)] [string] $AutomationAccountName,
        [Parameter(Mandatory)] [string] $ScheduleName,
        [Parameter(Mandatory)] [string] $Time,
        [Parameter(Mandatory)] [string] $TimeZone
    )

    $scheduleUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/schedules/$ScheduleName`?api-version=2024-10-23"
    $existingJson = az rest --method get --url $scheduleUri --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($existingJson)) {
        $existingSchedule = $existingJson | ConvertFrom-Json
        $existingStartTime = [string]$existingSchedule.properties.startTime
        $existingTimeZone = [string]$existingSchedule.properties.timeZone
        if ($existingTimeZone -eq $TimeZone -and -not [string]::IsNullOrWhiteSpace($existingStartTime)) {
            $zone = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZone)
            if ($existingStartTime -match '(Z|[+-]\d{2}:\d{2})$') {
                $existingLocal = [System.TimeZoneInfo]::ConvertTime(
                    [DateTimeOffset]::Parse($existingStartTime, [System.Globalization.CultureInfo]::InvariantCulture),
                    $zone
                )
            } else {
                $existingLocalDateTime = [DateTime]::Parse(
                    $existingStartTime,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
                )
                $existingLocal = [DateTimeOffset]::new(
                    [DateTime]::SpecifyKind($existingLocalDateTime, [DateTimeKind]::Unspecified),
                    $zone.GetUtcOffset($existingLocalDateTime)
                )
            }
            if ($existingLocal.ToString('HHmm') -eq $Time) {
                return $existingLocal.ToString('o')
            }
        }
    }

    $timeZoneInfo = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZone)
    $nowUtc = [DateTimeOffset]::UtcNow
    $localNow = [System.TimeZoneInfo]::ConvertTime($nowUtc, $timeZoneInfo)
    $hour = [int]$Time.Substring(0, 2)
    $minute = [int]$Time.Substring(2, 2)
    $candidateLocal = [DateTime]::SpecifyKind(
        [DateTime]::new($localNow.Year, $localNow.Month, $localNow.Day, $hour, $minute, 0),
        [DateTimeKind]::Unspecified
    )
    $candidate = [DateTimeOffset]::new($candidateLocal, $timeZoneInfo.GetUtcOffset($candidateLocal))
    if ($candidate -le $nowUtc.AddMinutes(15)) {
        $candidateLocal = $candidateLocal.AddDays(1)
        $candidate = [DateTimeOffset]::new($candidateLocal, $timeZoneInfo.GetUtcOffset($candidateLocal))
    }

    return $candidate.ToString('o')
}

function Wait-AutomationArmOperation {
    param(
        [AllowEmptyString()] [string] $OperationUri,
        [Parameter(Mandatory)] [hashtable] $Headers,
        [Parameter(Mandatory)] [string] $Description
    )

    if ([string]::IsNullOrWhiteSpace($OperationUri)) {
        return
    }

    for ($attempt = 1; $attempt -le 60; $attempt++) {
        $operation = Invoke-RestMethod -Method Get -Uri $OperationUri -Headers $Headers -ErrorAction Stop
        $status = [string]$operation.status
        if ($status -eq 'Succeeded') {
            return
        }
        if ($status -in @('Failed', 'Canceled')) {
            throw "$Description failed with status '$status'."
        }
        Start-Sleep -Seconds 2
    }

    throw "$Description did not complete within 120 seconds."
}

function Wait-AutomationRunbookPublished {
    param(
        [Parameter(Mandatory)] [string] $RunbookUri,
        [Parameter(Mandatory)] [hashtable] $Headers,
        [Parameter(Mandatory)] [string] $RunbookName
    )

    for ($attempt = 1; $attempt -le 60; $attempt++) {
        $runbook = Invoke-RestMethod -Method Get -Uri "$RunbookUri`?api-version=2024-10-23" -Headers $Headers -ErrorAction Stop
        $state = [string]$runbook.properties.state
        if ($state -eq 'Published') {
            return
        }
        if ($state -eq 'Suspended') {
            throw "Runbook '$RunbookName' entered the suspended state while publishing."
        }
        Start-Sleep -Seconds 2
    }

    throw "Runbook '$RunbookName' was not published within 120 seconds."
}

function Publish-AutomationRunbooks {
    param(
        [Parameter(Mandatory)] [string] $SubscriptionId,
        [Parameter(Mandatory)] [string] $ResourceGroupName,
        [Parameter(Mandatory)] [string] $AutomationAccountName,
        [Parameter(Mandatory)] [object[]] $Runbooks
    )

    $accessToken = Get-AzureArmAccessToken -SubscriptionId $SubscriptionId
    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        throw 'Unable to acquire an Azure Resource Manager token for runbook publication.'
    }
    $headers = @{ Authorization = "Bearer $accessToken" }

    foreach ($runbook in $Runbooks) {
        Write-Task "Publishing Automation runbook '$($runbook.name)'..."
        $baseUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/runbooks/$($runbook.name)"
        $content = [System.IO.File]::ReadAllText($runbook.path)
        $replaceResponse = Invoke-WebRequest `
            -Method Put `
            -Uri "$baseUri/draft/content?api-version=2024-10-23" `
            -Headers $headers `
            -ContentType 'text/plain; charset=utf-8' `
            -Body $content `
            -ErrorAction Stop
        Wait-AutomationArmOperation `
            -OperationUri ([string]$replaceResponse.Headers['Azure-AsyncOperation']) `
            -Headers $headers `
            -Description "Replacing draft content for '$($runbook.name)'"

        $publishResponse = Invoke-WebRequest `
            -Method Post `
            -Uri "$baseUri/publish?api-version=2024-10-23" `
            -Headers $headers `
            -ContentType 'application/json' `
            -Body '{}' `
            -ErrorAction Stop
        Wait-AutomationArmOperation `
            -OperationUri ([string]$publishResponse.Headers['Azure-AsyncOperation']) `
            -Headers $headers `
            -Description "Publishing '$($runbook.name)'"
        Wait-AutomationRunbookPublished `
            -RunbookUri $baseUri `
            -Headers $headers `
            -RunbookName $runbook.name
        Write-Exists "  Runbook '$($runbook.name)' published."
    }
}

function Set-AutomationJobSchedule {
    param(
        [Parameter(Mandatory)] [string] $SubscriptionId,
        [Parameter(Mandatory)] [string] $ResourceGroupName,
        [Parameter(Mandatory)] [string] $AutomationAccountName,
        [Parameter(Mandatory)] [string] $JobScheduleName,
        [Parameter(Mandatory)] [string] $ScheduleName,
        [Parameter(Mandatory)] [string] $RunbookName,
        [Parameter(Mandatory)] [hashtable] $RunbookParameters
    )

    $accessToken = Get-AzureArmAccessToken -SubscriptionId $SubscriptionId
    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        throw 'Unable to acquire an Azure Resource Manager token for Automation job scheduling.'
    }

    $headers = @{ Authorization = "Bearer $accessToken" }
    $jobScheduleUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/jobSchedules/$JobScheduleName`?api-version=2024-10-23"
    $body = @{
        properties = @{
            parameters = $RunbookParameters
            runbook = @{
                name = $RunbookName
            }
            schedule = @{
                name = $ScheduleName
            }
        }
    } | ConvertTo-Json -Depth 8

    Write-Task "Linking Automation runbook '$RunbookName' to schedule '$ScheduleName'..."
    $response = Invoke-WebRequest `
        -Method Put `
        -Uri $jobScheduleUri `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $body `
        -ErrorAction Stop
    Wait-AutomationArmOperation `
        -OperationUri ([string]$response.Headers['Azure-AsyncOperation']) `
        -Headers $headers `
        -Description "Linking runbook '$RunbookName' to schedule '$ScheduleName'"
    Write-Exists "  Runbook '$RunbookName' is linked to schedule '$ScheduleName'."
}

function Test-AzureResourceCurrent {
    param(
        [Parameter(Mandatory)] [string] $ResourceId,
        [Parameter(Mandatory)] [string] $Description
    )

    $resourceJson = az resource show --ids $ResourceId --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resourceJson)) {
        Write-Info "  Not current: $Description is missing."
        return $false
    }

    try {
        $resource = $resourceJson | ConvertFrom-Json
    } catch {
        Write-Info "  Not current: could not parse status for $Description."
        return $false
    }

    $state = if ($resource.properties -and $resource.properties.PSObject.Properties['provisioningState']) {
        [string]$resource.properties.provisioningState
    } else {
        ''
    }

    if (-not [string]::IsNullOrWhiteSpace($state) -and $state -ne 'Succeeded') {
        Write-Info "  Not current: $Description provisioning state is '$state'."
        return $false
    }

    return $true
}

function Test-OpenAiDeploymentCurrent {
    param(
        [Parameter(Mandatory)] [string] $ResourceGroupName,
        [Parameter(Mandatory)] [string] $AccountName,
        [Parameter(Mandatory)] [string] $DeploymentName
    )

    $state = az cognitiveservices account deployment show `
        --resource-group $ResourceGroupName `
        --name $AccountName `
        --deployment-name $DeploymentName `
        --query properties.provisioningState `
        --output tsv 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($state)) {
        Write-Info "  Not current: OpenAI model deployment '$DeploymentName' is missing."
        return $false
    }

    if ($state.Trim() -ne 'Succeeded') {
        Write-Info "  Not current: OpenAI model deployment '$DeploymentName' provisioning state is '$($state.Trim())'."
        return $false
    }

    return $true
}

function Test-EnterpriseDeploymentCurrent {
    param(
        [Parameter(Mandatory)] [string] $SubscriptionId,
        [Parameter(Mandatory)] [string] $CoreResourceGroupName,
        [Parameter(Mandatory)] [string] $NetworkResourceGroupName,
        [Parameter(Mandatory)] [string] $StorageAccountName,
        [Parameter(Mandatory)] [string] $KeyVaultName,
        [Parameter(Mandatory)] [string] $OpenAiAccountName,
        [Parameter(Mandatory)] [string] $HubName,
        [Parameter(Mandatory)] [string] $ProjectName,
        [Parameter(Mandatory)] [string] $HubManagedIdentityName,
        [Parameter(Mandatory)] [string] $VmManagedIdentityName,
        [Parameter(Mandatory)] [bool] $AutomationEnabled,
        [Parameter(Mandatory)] [bool] $DeployStorage,
        [Parameter(Mandatory)] [bool] $DeployLogAnalytics,
        [Parameter(Mandatory)] [bool] $DeployAiFoundry,
        [Parameter(Mandatory)] [bool] $DeployVm,
        [Parameter(Mandatory)] [string] $AutomationAccountName,
        [Parameter(Mandatory)] [string] $AutomationManagedIdentityName,
        [Parameter(Mandatory)] [object[]] $AutomationRunbooks,
        [Parameter(Mandatory)] [bool] $VmStartScheduleEnabled,
        [Parameter(Mandatory)] [string] $VmStartScheduleName,
        [Parameter(Mandatory)] [string] $VmStartScheduleStartTime,
        [Parameter(Mandatory)] [string] $VmStartScheduleTimeZone,
        [Parameter(Mandatory)] [bool] $RdpDeployerCleanupScheduleEnabled,
        [Parameter(Mandatory)] [string] $RdpDeployerCleanupScheduleName,
        [Parameter(Mandatory)] [string] $RdpDeployerCleanupScheduleStartTime,
        [Parameter(Mandatory)] [string] $RdpDeployerCleanupScheduleTimeZone,
        [Parameter(Mandatory)] [string] $VnetName,
        [Parameter(Mandatory)] [string] $VmName,
        [Parameter(Mandatory)] [string] $LogAnalyticsWorkspaceName,
        [Parameter(Mandatory)] [object[]] $ModelDeployments,
        [Parameter(Mandatory)] [bool] $PrivateAiWorkspacesOnly,
        [Parameter(Mandatory)] [bool] $VmAutoShutdownEnabled,
        [Parameter(Mandatory)] [string] $ExpectedDesiredStateHash
    )

    Write-Task 'Checking whether the existing deployment is already current...'

    $coreRgJson = az group show --name $CoreResourceGroupName --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($coreRgJson)) {
        Write-Info "  Not current: core resource group '$CoreResourceGroupName' is missing."
        return $false
    }

    $networkRgJson = az group show --name $NetworkResourceGroupName --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($networkRgJson)) {
        Write-Info "  Not current: network resource group '$NetworkResourceGroupName' is missing."
        return $false
    }

    $coreRg = $coreRgJson | ConvertFrom-Json
    $existingDesiredStateHash = if ($coreRg.tags -and $coreRg.tags.PSObject.Properties['desiredStateHash']) {
        [string]$coreRg.tags.desiredStateHash
    } else {
        ''
    }

    if ($existingDesiredStateHash -ne $ExpectedDesiredStateHash) {
        if ([string]::IsNullOrWhiteSpace($existingDesiredStateHash)) {
            Write-Info '  Not current: deployed desired-state hash is not recorded yet.'
        } else {
            Write-Info '  Not current: deployed desired-state hash differs from local source/configuration.'
        }
        return $false
    }

    $subScope = "/subscriptions/$SubscriptionId"
    $coreScope = "$subScope/resourceGroups/$CoreResourceGroupName"
    $networkScope = "$subScope/resourceGroups/$NetworkResourceGroupName"

    # Always-on components. These have no deployment flag because they hold deployment state
    # (Key Vault), or because every other component depends on them (networking, Azure OpenAI,
    # managed identities).
    $resourceChecks = @(
        @{ Id = "$coreScope/providers/Microsoft.KeyVault/vaults/$KeyVaultName"; Description = "Key Vault '$KeyVaultName'" }
        @{ Id = "$coreScope/providers/Microsoft.CognitiveServices/accounts/$OpenAiAccountName"; Description = "Azure OpenAI account '$OpenAiAccountName'" }
        @{ Id = "$coreScope/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$HubManagedIdentityName"; Description = "Hub managed identity '$HubManagedIdentityName'" }
        @{ Id = "$coreScope/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$VmManagedIdentityName"; Description = "VM managed identity '$VmManagedIdentityName'" }
        @{ Id = "$networkScope/providers/Microsoft.Network/virtualNetworks/$VnetName"; Description = "Virtual network '$VnetName'" }
        @{ Id = "$networkScope/providers/Microsoft.Network/privateEndpoints/$KeyVaultName-pe"; Description = "Key Vault private endpoint '$KeyVaultName-pe'" }
        @{ Id = "$networkScope/providers/Microsoft.Network/privateEndpoints/$OpenAiAccountName-account-pe"; Description = "OpenAI private endpoint '$OpenAiAccountName-account-pe'" }
        @{ Id = "$networkScope/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"; Description = "Key Vault private DNS zone" }
        @{ Id = "$networkScope/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"; Description = "OpenAI private DNS zone" }
        @{ Id = "$networkScope/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"; Description = "Storage private DNS zone" }
        @{ Id = "$networkScope/providers/Microsoft.Network/privateDnsZones/privatelink.api.azureml.ms"; Description = "Azure ML private DNS zone" }
        @{ Id = "$networkScope/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net/virtualNetworkLinks/vnet-link"; Description = "Key Vault private DNS VNet link" }
        @{ Id = "$networkScope/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com/virtualNetworkLinks/vnet-link"; Description = "OpenAI private DNS VNet link" }
        @{ Id = "$networkScope/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/vnet-link"; Description = "Storage private DNS VNet link" }
        @{ Id = "$networkScope/providers/Microsoft.Network/privateDnsZones/privatelink.api.azureml.ms/virtualNetworkLinks/vnet-link"; Description = "Azure ML private DNS VNet link" }
    )

    # Flagged components: present when the flag is true, absent when it is false.
    $storageResources = @(
        @{ Id = "$coreScope/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"; Description = "Storage account '$StorageAccountName'" }
        @{ Id = "$networkScope/providers/Microsoft.Network/privateEndpoints/$StorageAccountName-blob-pe"; Description = "Storage private endpoint '$StorageAccountName-blob-pe'" }
    )
    $logAnalyticsResources = @(
        @{ Id = "$coreScope/providers/Microsoft.OperationalInsights/workspaces/$LogAnalyticsWorkspaceName"; Description = "Log Analytics workspace '$LogAnalyticsWorkspaceName'" }
    )
    $aiFoundryResources = @(
        @{ Id = "$coreScope/providers/Microsoft.MachineLearningServices/workspaces/$HubName"; Description = "AI Hub '$HubName'" }
        @{ Id = "$coreScope/providers/Microsoft.MachineLearningServices/workspaces/$ProjectName"; Description = "AI Project '$ProjectName'" }
    )
    if ($PrivateAiWorkspacesOnly) {
        $aiFoundryResources += @{ Id = "$networkScope/providers/Microsoft.Network/privateEndpoints/$HubName-pe"; Description = "AI Hub private endpoint '$HubName-pe'" }
    }
    $vmResources = @(
        @{ Id = "$coreScope/providers/Microsoft.Compute/virtualMachines/$VmName"; Description = "Jumpbox VM '$VmName'" }
        @{ Id = "$networkScope/providers/Microsoft.Network/networkSecurityGroups/$VmName-nsg"; Description = "VM NSG '$VmName-nsg'" }
        @{ Id = "$networkScope/providers/Microsoft.Network/networkInterfaces/$VmName-nic"; Description = "VM NIC '$VmName-nic'" }
        @{ Id = "$networkScope/providers/Microsoft.Network/publicIPAddresses/$VmName-pip"; Description = "VM public IP '$VmName-pip'" }
        @{ Id = "$coreScope/providers/Microsoft.Compute/disks/$VmName-osdisk"; Description = "VM OS disk '$VmName-osdisk'" }
        @{ Id = "$coreScope/providers/Microsoft.Compute/virtualMachines/$VmName/extensions/AzureMonitorWindowsAgent"; Description = "Azure Monitor Agent VM extension" }
        @{ Id = "$coreScope/providers/Microsoft.Compute/virtualMachines/$VmName/extensions/IaaSAntimalware"; Description = "IaaS Antimalware VM extension" }
        @{ Id = "$coreScope/providers/Microsoft.Compute/virtualMachines/$VmName/extensions/AzureDiskEncryption"; Description = "Azure Disk Encryption VM extension" }
    )
    if ($VmAutoShutdownEnabled) {
        $vmResources += @{ Id = "$coreScope/providers/Microsoft.DevTestLab/schedules/shutdown-computevm-$VmName"; Description = "VM auto-shutdown schedule 'shutdown-computevm-$VmName'" }
    }

    # Resources that must be gone when their flag is false. Checking these keeps the no-op guard
    # honest: a disabled component that still exists forces the deployment path, which removes it.
    $absentChecks = @()
    foreach ($flagged in @(
        @{ Enabled = $DeployStorage; Resources = $storageResources }
        @{ Enabled = $DeployLogAnalytics; Resources = $logAnalyticsResources }
        @{ Enabled = $DeployAiFoundry; Resources = $aiFoundryResources }
        @{ Enabled = $DeployVm; Resources = $vmResources }
    )) {
        if ($flagged.Enabled) {
            $resourceChecks += $flagged.Resources
        } else {
            $absentChecks += $flagged.Resources
        }
    }

    if (-not $AutomationEnabled) {
        $absentChecks += @{ Id = "$coreScope/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName"; Description = "Automation Account '$AutomationAccountName'" }
        $absentChecks += @{ Id = "$coreScope/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$AutomationManagedIdentityName"; Description = "Automation managed identity '$AutomationManagedIdentityName'" }
    }

    foreach ($absentCheck in $absentChecks) {
        az resource show --ids $absentCheck.Id --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Info "  Not current: $($absentCheck.Description) still exists but its deployment flag is false."
            return $false
        }
    }

    if ($AutomationEnabled) {
        $resourceChecks += @{ Id = "$coreScope/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$AutomationManagedIdentityName"; Description = "Automation managed identity '$AutomationManagedIdentityName'" }
        $resourceChecks += @{ Id = "$coreScope/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName"; Description = "Automation Account '$AutomationAccountName'" }
        foreach ($runbook in $AutomationRunbooks) {
            $resourceChecks += @{ Id = "$coreScope/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/runbooks/$($runbook.name)"; Description = "Automation runbook '$($runbook.name)'" }
        }
        $jobSchedules = $null
        if ($VmStartScheduleEnabled) {
            $resourceChecks += @{ Id = "$coreScope/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/schedules/$VmStartScheduleName"; Description = "Automation schedule '$VmStartScheduleName'" }
        }
        if ($RdpDeployerCleanupScheduleEnabled) {
            $resourceChecks += @{ Id = "$coreScope/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/schedules/$RdpDeployerCleanupScheduleName"; Description = "Automation schedule '$RdpDeployerCleanupScheduleName'" }
        }
    }

    foreach ($resourceCheck in $resourceChecks) {
        if (-not (Test-AzureResourceCurrent -ResourceId $resourceCheck.Id -Description $resourceCheck.Description)) {
            return $false
        }
    }

    if ($AutomationEnabled) {
        $scheduleChecks = @()
        if ($VmStartScheduleEnabled) {
            $scheduleChecks += @{
                Name = $VmStartScheduleName
                ExpectedStartTime = $VmStartScheduleStartTime
                ExpectedTimeZone = $VmStartScheduleTimeZone
                ExpectedFrequency = 'Day'
                ExpectedInterval = 1
            }
        }
        if ($RdpDeployerCleanupScheduleEnabled) {
            $scheduleChecks += @{
                Name = $RdpDeployerCleanupScheduleName
                ExpectedStartTime = $RdpDeployerCleanupScheduleStartTime
                ExpectedTimeZone = $RdpDeployerCleanupScheduleTimeZone
                ExpectedFrequency = 'Week'
                ExpectedInterval = 1
            }
        }
        foreach ($scheduleCheck in $scheduleChecks) {
            $scheduleId = "$coreScope/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/schedules/$($scheduleCheck.Name)"
            $scheduleUri = "https://management.azure.com${scheduleId}?api-version=2024-10-23"
            $scheduleJson = az rest --method get --url $scheduleUri --output json 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($scheduleJson)) {
                Write-Info "  Not current: unable to read Automation schedule '$($scheduleCheck.Name)'."
                return $false
            }

            $schedule = $scheduleJson | ConvertFrom-Json
            $properties = $schedule.properties
            if ([string]$properties.frequency -ne $scheduleCheck.ExpectedFrequency -or
                [int]$properties.interval -ne $scheduleCheck.ExpectedInterval -or
                [string]$properties.timeZone -ne $scheduleCheck.ExpectedTimeZone) {
                Write-Info "  Not current: Automation schedule '$($scheduleCheck.Name)' has drifted schedule properties."
                return $false
            }

            try {
                $actualStartTime = [DateTimeOffset]::Parse(
                    [string]$properties.startTime,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind
                )
                $expectedStartTime = [DateTimeOffset]::Parse(
                    $scheduleCheck.ExpectedStartTime,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind
                )
            } catch {
                Write-Info "  Not current: Automation schedule '$($scheduleCheck.Name)' has an invalid start time."
                return $false
            }
            if ($actualStartTime.ToUniversalTime() -ne $expectedStartTime.ToUniversalTime()) {
                Write-Info "  Not current: Automation schedule '$($scheduleCheck.Name)' start time has drifted."
                return $false
            }
        }

        foreach ($runbook in $AutomationRunbooks) {
            $runbookId = "$coreScope/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/runbooks/$($runbook.name)"
            $deployedHash = az resource show --ids $runbookId --query tags.sourceHash --output tsv 2>$null
            $deployedHashValue = if ([string]::IsNullOrWhiteSpace($deployedHash)) { '' } else { $deployedHash.Trim() }
            if ($LASTEXITCODE -ne 0 -or $deployedHashValue -ne $runbook.sourceHash) {
                Write-Info "  Not current: Automation runbook '$($runbook.name)' source hash differs from the repository."
                return $false
            }
        }

        if ($VmStartScheduleEnabled) {
            $jobSchedulesUri = "https://management.azure.com${coreScope}/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/jobSchedules?api-version=2024-10-23"
            $jobSchedulesJson = az rest --method get --url $jobSchedulesUri --output json 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($jobSchedulesJson)) {
                Write-Info '  Not current: unable to read Automation job schedules.'
                return $false
            }
            $jobSchedules = ($jobSchedulesJson | ConvertFrom-Json).value
            $matchingJob = @($jobSchedules | Where-Object {
                $_.properties.runbook.name -eq 'start-vm' -and $_.properties.schedule.name -eq $VmStartScheduleName
            })
            if ($matchingJob.Count -eq 0) {
                Write-Info "  Not current: runbook 'start-vm' is not linked to schedule '$VmStartScheduleName'."
                return $false
            }
        }
        if ($RdpDeployerCleanupScheduleEnabled) {
            if (-not $jobSchedules) {
                $jobSchedulesUri = "https://management.azure.com${coreScope}/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/jobSchedules?api-version=2024-10-23"
                $jobSchedulesJson = az rest --method get --url $jobSchedulesUri --output json 2>$null
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($jobSchedulesJson)) {
                    Write-Info '  Not current: unable to read Automation job schedules.'
                    return $false
                }
                $jobSchedules = ($jobSchedulesJson | ConvertFrom-Json).value
            }
            $matchingCleanupJob = @($jobSchedules | Where-Object {
                $_.properties.runbook.name -eq 'delete-rdp-deployer-rule' -and $_.properties.schedule.name -eq $RdpDeployerCleanupScheduleName
            })
            if ($matchingCleanupJob.Count -eq 0) {
                Write-Info "  Not current: runbook 'delete-rdp-deployer-rule' is not linked to schedule '$RdpDeployerCleanupScheduleName'."
                return $false
            }
        }
    }

    foreach ($modelDeployment in $ModelDeployments) {
        if (-not (Test-OpenAiDeploymentCurrent -ResourceGroupName $CoreResourceGroupName -AccountName $OpenAiAccountName -DeploymentName $modelDeployment.deploymentName)) {
            return $false
        }
    }

    Write-Exists '  Existing environment is complete and matches the current desired-state hash.'
    return $true
}


Write-Task 'Validating Azure CLI authentication context...'
az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Info 'No active Azure session detected - running az login...'
    az login
}

Show-AzureContext

$subscriptionId = (az account show --query id --output tsv).Trim()
$NameSuffix     = ($subscriptionId -replace '-', '').Substring(0, 4).ToLower()
Write-Host "Resource name suffix (subscription-derived): " -NoNewline; Write-Host $NameSuffix -ForegroundColor Red

az account set --subscription $subscriptionId 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Unable to set Azure CLI subscription context to '$subscriptionId'."
    exit 1
}

Write-Task "Loading environment configuration for '$EnvironmentSuffix'..."
$config = Read-EnterpriseEnvironmentConfig -ScriptRoot $scriptRoot -EnvironmentSuffix $EnvironmentSuffix -NameSuffix $NameSuffix

# Assign all config variables immediately after loading config
$BaseName                        = $config.baseName
$Location                        = $config.location
$VnetAddressSpace                = $config.vnetAddressSpace
$ServicesSubnetAddressPrefix     = $config.servicesSubnetAddressPrefix
$VmSubnetAddressPrefix           = $config.vmSubnetAddressPrefix
$VmAcceleratedNetworking         = Convert-ToBoolean -Value $config.vmAcceleratedNetworking -Default $true
$VmPublicIpDnsNameLabel          = [string]$config.vmPublicIpDnsNameLabel
$CoreResourceGroupName           = $config.coreResourceGroupName
$NetworkResourceGroupName        = $config.networkResourceGroupName
$VnetName                        = $config.vnetName
$SkuName                         = $config.skuName
$StorageAccessTier               = $config.storageAccessTier
$StorageBlobSoftDeleteDays       = [int]$config.storageBlobSoftDeleteRetentionDays
$StorageContainerSoftDeleteDays  = [int]$config.storageContainerSoftDeleteRetentionDays
$KeyVaultSoftDeleteDays          = [int]$config.keyVaultSoftDeleteRetentionDays
$ModelDeployments                = @($config.modelDeployments)
$ModelDeploymentName             = [string]$ModelDeployments[0].deploymentName
$SecondaryModelDeploymentName    = [string]$ModelDeployments[1].deploymentName
$AdminActors                  = @($config.adminActors)
$UserActors                   = @($config.userActors)
$AdminObjectIds               = @([string]$config.adminObjectIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
$VmAdminUsername                 = $config.vmAdminUsername
$VmSize                          = $config.vmSize
$VmImagePublisher                = $config.vmImagePublisher
$VmImageOffer                    = $config.vmImageOffer
$VmImageSku                      = $config.vmImageSku
$VmImageVersion                  = $config.vmImageVersion
$VmOsDiskStorageAccountType      = $config.vmOsDiskStorageAccountType
$MlApiVersion                    = $config.mlApiVersion
$VmUseSpot                       = Convert-ToBoolean -Value $config.vmUseSpot -Default $true
$VmSpotMaxPrice                  = [int]$config.vmSpotMaxPrice
$VmAutoShutdownEnabled           = Convert-ToBoolean -Value $config.vmAutoShutdownEnabled -Default $true
$VmAutoShutdownTime              = $config.vmAutoShutdownTime
$VmAutoShutdownTimeZone          = $config.vmAutoShutdownTimeZone
$VmGuestTimeZone                 = $config.vmGuestTimeZone
$AutomationEnabled               = Convert-ToBoolean -Value $config.deployAutomation -Default $true
$DeployStorage                   = Convert-ToBoolean -Value $config.deployStorage -Default $true
$DeployLogAnalytics              = Convert-ToBoolean -Value $config.deployLogAnalytics -Default $true
$DeployAiFoundry                 = Convert-ToBoolean -Value $config.deployAiFoundry -Default $true
$DeployVm                        = Convert-ToBoolean -Value $config.deployVm -Default $true
$DeployAutomation                = $AutomationEnabled
$AutomationRuntimeVersion        = $config.automationRuntimeVersion
$AutomationAzVersion             = $config.automationAzVersion
$VmStartScheduleEnabled          = Convert-ToBoolean -Value $config.vmStartScheduleEnabled -Default $true
$VmStartScheduleTime             = $config.vmStartScheduleTime
$VmStartScheduleTimeZone         = $config.vmStartScheduleTimeZone
$RdpDeployerCleanupScheduleEnabled = Convert-ToBoolean -Value $config.rdpDeployerCleanupScheduleEnabled -Default $true
$RdpDeployerCleanupScheduleTime    = $config.rdpDeployerCleanupScheduleTime
$RdpDeployerCleanupScheduleTimeZone = $config.rdpDeployerCleanupScheduleTimeZone
$PrivateAiWorkspacesOnly         = Convert-ToBoolean -Value $config.privateAiWorkspacesOnly -Default $true
$EnableAuditDiagnostics          = Convert-ToBoolean -Value $config.enableAuditDiagnostics -Default $true
$LogAnalyticsRetentionDays       = [int]$config.logAnalyticsRetentionDays
$LogAnalyticsDailyQuotaGb        = $config.logAnalyticsDailyQuotaGb
$LogAnalyticsWorkspaceName       = $config.lawWorkspaceName
$ConfiguredRdpAllowedIpCidrs     = @($config.rdpAllowedIpCidrs)
$desiredStateHash                = Get-DeploymentDesiredStateHash -ScriptRoot $scriptRoot -EnvironmentSuffix $EnvironmentSuffix
$deploymentName = ("enterprise-$BaseName-$EnvironmentSuffix-$Location-$(Get-Date -Format 'yyyyMMddHHmmss')").ToLower()
$templatePath = Join-Path $scriptRoot '..\bicep\templates\main.bicep'
if (-not (Test-Path $templatePath)) {
    throw "Required template file not found: $templatePath"
}
$templateFile = Resolve-Path $templatePath
$tempDir      = [System.IO.Path]::GetTempPath()
$parameterFile = Join-Path $tempDir "enterprise-$EnvironmentSuffix.parameters.$PID.json"
$hubName             = $config.hubName
$projectName         = $config.projectName
$storageAccountName  = $config.storageAccountName
$containerName       = $config.containerName
$keyVaultName        = $config.keyVaultName
$openAiAccountName   = $config.openAiAccountName
$vmName              = $config.vmName
$hubManagedIdentityName = $config.hubManagedIdentityName
$vmManagedIdentityName = $config.vmManagedIdentityName
$automationManagedIdentityName = $config.automationManagedIdentityName
$automationAccountName = $config.automationAccountName
$vmStartScheduleName = $config.vmStartScheduleName
$rdpDeployerCleanupScheduleName = $config.rdpDeployerCleanupScheduleName
$legacyManagedIdentityName = $config.legacyManagedIdentityName
$automationRunbooks = if ($AutomationEnabled) {
    @(Get-AutomationRunbookDescriptors -ScriptRoot $scriptRoot)
} else {
    @()
}
$vmStartScheduleStartTime = if ($AutomationEnabled -and $VmStartScheduleEnabled) {
    Get-AutomationScheduleStartTime `
        -SubscriptionId $subscriptionId `
        -ResourceGroupName $CoreResourceGroupName `
        -AutomationAccountName $automationAccountName `
        -ScheduleName $vmStartScheduleName `
        -Time $VmStartScheduleTime `
        -TimeZone $VmStartScheduleTimeZone
} else {
    ''
}
$rdpDeployerCleanupScheduleStartTime = if ($AutomationEnabled -and $RdpDeployerCleanupScheduleEnabled) {
    Get-AutomationScheduleStartTime `
        -SubscriptionId $subscriptionId `
        -ResourceGroupName $CoreResourceGroupName `
        -AutomationAccountName $automationAccountName `
        -ScheduleName $rdpDeployerCleanupScheduleName `
        -Time $RdpDeployerCleanupScheduleTime `
        -TimeZone $RdpDeployerCleanupScheduleTimeZone
} else {
    ''
}

$tenantIdRaw = az account show --query tenantId --output tsv 2>$null
$tenantId = if (-not [string]::IsNullOrWhiteSpace($tenantIdRaw)) { $tenantIdRaw.Trim() } else { '' }
Write-Info "  TenantId (for first-run device login): $tenantId"

$adminUpn = if ($AdminObjectIds.Count -gt 0) { $AdminObjectIds[0] } else { '' }

if ($Action -eq 'myip') {
    Write-Error "The 'myip' action is unavailable because subscription policy requires Key Vault and Storage public network access to remain disabled. Use the VM inside the VNet for data-plane access."
    exit 1
}

if (-not $WhatIf -and -not $ForceRedeploy -and -not $ForceAppBootstrap) {
    $deploymentIsCurrent = Test-EnterpriseDeploymentCurrent `
        -SubscriptionId $subscriptionId `
        -CoreResourceGroupName $CoreResourceGroupName `
        -NetworkResourceGroupName $NetworkResourceGroupName `
        -StorageAccountName $storageAccountName `
        -KeyVaultName $keyVaultName `
        -OpenAiAccountName $openAiAccountName `
        -HubName $hubName `
        -ProjectName $projectName `
        -HubManagedIdentityName $hubManagedIdentityName `
        -VmManagedIdentityName $vmManagedIdentityName `
        -AutomationEnabled $AutomationEnabled `
        -DeployStorage $DeployStorage `
        -DeployLogAnalytics $DeployLogAnalytics `
        -DeployAiFoundry $DeployAiFoundry `
        -DeployVm $DeployVm `
        -AutomationAccountName $automationAccountName `
        -AutomationManagedIdentityName $automationManagedIdentityName `
        -AutomationRunbooks $automationRunbooks `
        -VmStartScheduleEnabled $VmStartScheduleEnabled `
        -VmStartScheduleName $vmStartScheduleName `
        -VmStartScheduleStartTime $vmStartScheduleStartTime `
        -VmStartScheduleTimeZone $VmStartScheduleTimeZone `
        -RdpDeployerCleanupScheduleEnabled $RdpDeployerCleanupScheduleEnabled `
        -RdpDeployerCleanupScheduleName $rdpDeployerCleanupScheduleName `
        -RdpDeployerCleanupScheduleStartTime $rdpDeployerCleanupScheduleStartTime `
        -RdpDeployerCleanupScheduleTimeZone $RdpDeployerCleanupScheduleTimeZone `
        -VnetName $VnetName `
        -VmName $vmName `
        -LogAnalyticsWorkspaceName $LogAnalyticsWorkspaceName `
        -ModelDeployments $ModelDeployments `
        -PrivateAiWorkspacesOnly $PrivateAiWorkspacesOnly `
        -VmAutoShutdownEnabled $VmAutoShutdownEnabled `
        -ExpectedDesiredStateHash $desiredStateHash

    if ($deploymentIsCurrent) {
        Write-Exists "Deployment for environment '$EnvironmentSuffix' is already current. Exiting without redeploying or changing resources."
        exit 0
    }
} elseif ($ForceRedeploy) {
    Write-Info 'ForceRedeploy supplied — skipping current-deployment early exit.'
} elseif ($ForceAppBootstrap) {
    Write-Info 'ForceAppBootstrap supplied — skipping current-deployment early exit.'
}

Register-RequiredResourceProviders -SubscriptionId $subscriptionId

Write-Task 'Resolving the deploying identity...'
$accountTypeRaw = az account show --query 'user.type' --output tsv 2>$null
$accountType = if (-not [string]::IsNullOrWhiteSpace($accountTypeRaw)) { $accountTypeRaw.Trim() } else { '' }
if ($accountType -eq 'servicePrincipal') {
    $appIdRaw = az account show --query 'user.name' --output tsv 2>$null
    $appId = if (-not [string]::IsNullOrWhiteSpace($appIdRaw)) { $appIdRaw.Trim() } else { '' }
    $deployingObjectIdRaw = az ad sp show --id $appId --query id --output tsv 2>$null
    $deployingObjectId = if (-not [string]::IsNullOrWhiteSpace($deployingObjectIdRaw)) { $deployingObjectIdRaw.Trim() } else { '' }
} else {
    $signedInUserIdRaw = az ad signed-in-user show --query id --output tsv 2>$null
    $deployingObjectId = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($signedInUserIdRaw)) {
        $signedInUserIdRaw.Trim()
    } elseif ($AdminObjectIds.Count -gt 0) {
        $AdminObjectIds[0]
    } else {
        ''
    }
}

if ([string]::IsNullOrWhiteSpace($deployingObjectId)) {
    Write-Error 'Could not determine the object ID of the current identity. Ensure you are logged in with az login.'
    exit 1
}
Write-Info "  Deploying identity object ID: $deployingObjectId  (type: $accountType)"
$deployingPrincipalType = if ($accountType -eq 'servicePrincipal') { 'ServicePrincipal' } else { 'User' }

$subScope = "/subscriptions/$subscriptionId"
$skipRoleElevation = [bool]($isCi -or $SkipRoleElevation)
if ($skipRoleElevation) {
    Write-Info '  Automatic role elevation is disabled for this run (CI context or -SkipRoleElevation).'
}
$hasRoleAssignWrite = Initialize-RoleAssignmentWritePermission `
    -PrincipalObjectId $deployingObjectId `
    -PrincipalType $deployingPrincipalType `
    -SubscriptionId $subscriptionId `
    -SkipElevation $skipRoleElevation

if (-not $hasRoleAssignWrite) {
    Write-Error @"
The deploying identity ($deployingObjectId, type: $accountType) does not have 'Owner' or
'User Access Administrator' role at subscription scope '$subScope', and this script could not
grant it automatically.

This role is required because the Bicep template creates Azure RBAC role assignments
for the managed identities (Storage Blob Data Contributor, Key Vault Secrets User,
Cognitive Services OpenAI User).

Automatic remediation attempts that were made:
  1. Self-assigning 'User Access Administrator' at the subscription scope.
  2. Entra 'Access management for Azure resources' elevation (interactive users only;
     requires the Entra Global Administrator role).

One-time fix — have an administrator with role-assignment write permission at this
subscription scope run this single-line command (compatible with PowerShell):
  az role assignment create --role "User Access Administrator" --assignee "$deployingObjectId" --scope "$subScope"

The deploying identity also needs resource deployment permissions, such as Contributor.
The Entra Global Administrator role alone does not grant Azure subscription access.
In the portal, select the actual deploying user or service principal:
  Subscription -> Access control (IAM) -> Add role assignment -> User Access Administrator.

CI note: pipeline service principals cannot self-elevate. Grant the role once, out of band.
"@
    exit 1
}

$createdDateFromRg = az group show --name $CoreResourceGroupName --query "tags.createdDate" --output tsv 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($createdDateFromRg)) {
    # Preserve the original creation date so redeployments do not overwrite it.
    # Bicep receives this as resourceCreatedDate and stores it on the createdDate tag.
    $createdDateTagValue = $createdDateFromRg.Trim()
} else {
    # First deploy: no existing RG tag — Bicep will treat today as the creation date.
    $createdDateTagValue = ''
}

# Build the semantic (non-date) tags passed to Bicep.
# createdDate and lastModifiedDate are intentionally excluded here:
# main.bicep computes them via utcNow() and the resourceCreatedDate parameter,
# ensuring dates are always accurate without manual maintenance.
$deploymentTags = @{
    environment = if ([string]::IsNullOrWhiteSpace($config.tagEnvironment)) { $EnvironmentSuffix } else { $config.tagEnvironment }
    project = if ([string]::IsNullOrWhiteSpace($config.tagProject)) { $BaseName } else { $config.tagProject }
    workload = if ([string]::IsNullOrWhiteSpace($config.tagWorkload)) { 'enterprise-ai-foundry' } else { $config.tagWorkload }
    managedBy = if ([string]::IsNullOrWhiteSpace($config.tagManagedBy)) { 'bicep' } else { $config.tagManagedBy }
    desiredStateHash = $desiredStateHash
}

$localPublicIp = ''
if ($DeployVm) {
    Write-Task 'Detecting public IP address for the VM RDP allow rule...'
    $localPublicIp = Get-PublicIpAddress
    if ([string]::IsNullOrWhiteSpace($localPublicIp)) {
        if ($ConfiguredRdpAllowedIpCidrs.Count -eq 0) {
            Write-Error 'Could not determine the public IP of this machine and rdpAllowedIpCidrs is empty. Cannot configure restricted RDP access.'
            exit 1
        }
        Write-Info '  Warning: could not detect this machine public IP; using only rdpAllowedIpCidrs from configuration.'
    } else {
        Write-Info "  Public IP detected: $localPublicIp"
    }
} else {
    Write-Info '  VM deployment is disabled — no RDP allow rules will be passed to Bicep.'
}

$rdpAllowRules = [System.Collections.Generic.List[object]]::new()
if ($DeployVm -and $ConfiguredRdpAllowedIpCidrs.Count -gt 0) {
    $rdpAllowRules.Add(@{
        name = 'allow-rdp-user'
        sourceAddressPrefixes = @($ConfiguredRdpAllowedIpCidrs)
    })
}
if ($DeployVm -and -not [string]::IsNullOrWhiteSpace($localPublicIp)) {
    $rdpAllowRules.Add(@{
        name = 'allow-rdp-deployer'
        sourceAddressPrefixes = @($localPublicIp)
    })
}

# ----------------------------------------------------------------
# VM admin password resolution.
#
# Reruns must never silently change a password the jumpbox already has.
# Resolution order:
#   1. -VmAdminPassword            -> use it, store it, apply it.
#   2. -RotateVmPassword           -> generate a new one deliberately.
#   3. VM absent or being recreated-> generate one (there is no password to keep).
#   4. Local credential file       -> reuse the exact value from the last run.
#   5. Otherwise                   -> preserve: the VM keeps its current password.
#                                     Nothing is applied, synced, or written.
# ----------------------------------------------------------------
$repositoryRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path
$credentialDirectory = Join-Path $repositoryRoot '.local\credentials'
$credentialFile = Join-Path $credentialDirectory "vm-$EnvironmentSuffix.credentials.txt"
$preserveExistingVmPassword = $false
$vmPasswordOrigin = 'supplied'

if ([string]::IsNullOrWhiteSpace($VmAdminPassword)) {
    $vmWillBeCreatedOrRecreated = -not (Test-ExistingVmRetainsPassword `
        -ResourceGroupName $CoreResourceGroupName `
        -VmName $vmName `
        -UseSpot $VmUseSpot `
        -VmDeploymentEnabled $DeployVm)

    if (-not $DeployVm) {
        $preserveExistingVmPassword = $true
        $vmPasswordOrigin = 'notApplicable'
        $VmAdminPassword = New-SecurePassword
        Write-Info '  VM deployment is disabled — no VM password is generated, applied, or stored.'
    } elseif ($RotateVmPassword -or $vmWillBeCreatedOrRecreated) {
        if ($isCi) {
            Write-Error 'VM_ADMIN_PASSWORD was not supplied. CI deployments must pass -VmAdminPassword from a protected secret.'
            exit 1
        }
        $VmAdminPassword = New-SecurePassword
        $vmPasswordOrigin = 'generated'
        if ($RotateVmPassword) {
            Write-Needed "  -RotateVmPassword supplied — generating a new password for VM '$vmName'."
        } else {
            Write-Exists 'Generated a new VM admin password because the VM is being created.'
        }
    } else {
        $storedVmPassword = Get-StoredVmCredentialPassword -CredentialFilePath $credentialFile
        if (-not [string]::IsNullOrWhiteSpace($storedVmPassword)) {
            $VmAdminPassword = $storedVmPassword
            $vmPasswordOrigin = 'reused'
            Write-Exists "  Reusing the existing VM password recorded for '$vmName' — it is not being changed."
        } else {
            $preserveExistingVmPassword = $true
            $vmPasswordOrigin = 'preserved'
            # ARM ignores osProfile.adminPassword for an existing VM, so this throwaway value
            # satisfies the required template parameter without ever reaching the guest OS.
            $VmAdminPassword = New-SecurePassword
            Write-Exists "  VM '$vmName' already has a password from a previous run — keeping it unchanged."
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($VmAdminPassword)) {
    $VmAdminPassword = $VmAdminPassword.Trim()
}

$deploymentParameters = @{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = @{
        baseName = @{ value = $BaseName }
        environmentSuffix = @{ value = $EnvironmentSuffix }
        nameSuffix = @{ value = $NameSuffix }
        location = @{ value = $Location }
        addressSpace = @{ value = $VnetAddressSpace }
        servicesSubnetAddressPrefix = @{ value = $ServicesSubnetAddressPrefix }
        vmSubnetAddressPrefix = @{ value = $VmSubnetAddressPrefix }
        vmAcceleratedNetworking = @{ value = $VmAcceleratedNetworking }
        vmPublicIpDnsNameLabel = @{ value = $VmPublicIpDnsNameLabel }
        skuName = @{ value = $SkuName }
        storageAccessTier = @{ value = $StorageAccessTier }
        storageBlobSoftDeleteRetentionDays = @{ value = $StorageBlobSoftDeleteDays }
        storageContainerSoftDeleteRetentionDays = @{ value = $StorageContainerSoftDeleteDays }
        keyVaultSoftDeleteRetentionDays = @{ value = $KeyVaultSoftDeleteDays }
        adminActors = @{ value = @($AdminActors | ForEach-Object {
            @{
                objectId = $_.objectId
                principalType = $_.principalType
            }
        }) }
        userActors = @{ value = @($UserActors | ForEach-Object {
            @{
                objectId = $_.objectId
                principalType = $_.principalType
            }
        }) }
        adminObjectIds = @{ value = @($AdminObjectIds) }
        modelDeployments = @{ value = @($ModelDeployments | ForEach-Object {
            @{
                deploymentName = [string]$_.deploymentName
                modelName = [string]$_.modelName
                modelVersion = [string]$_.modelVersion
                skuName = [string]$_.skuName
                capacityK = [int]$_.capacityK
            }
        }) }
        vmAdminUsername = @{ value = $VmAdminUsername }
        vmAdminPassword = @{ value = $VmAdminPassword }
        vmSize = @{ value = $VmSize }
        vmImagePublisher = @{ value = $VmImagePublisher }
        vmImageOffer = @{ value = $VmImageOffer }
        vmImageSku = @{ value = $VmImageSku }
        vmImageVersion = @{ value = $VmImageVersion }
        vmOsDiskStorageAccountType = @{ value = $VmOsDiskStorageAccountType }
        tags = @{ value = $deploymentTags }
        vmUseSpot = @{ value = $VmUseSpot }
        vmSpotMaxPrice = @{ value = $VmSpotMaxPrice }
        vmAutoShutdownEnabled = @{ value = $VmAutoShutdownEnabled }
        vmAutoShutdownTime = @{ value = $VmAutoShutdownTime }
        vmAutoShutdownTimeZone = @{ value = $VmAutoShutdownTimeZone }
        deployStorage = @{ value = $DeployStorage }
        deployLogAnalytics = @{ value = $DeployLogAnalytics }
        deployAiFoundry = @{ value = $DeployAiFoundry }
        deployVm = @{ value = $DeployVm }
        deployAutomation = @{ value = $DeployAutomation }
        automationRuntimeVersion = @{ value = $AutomationRuntimeVersion }
        automationAzVersion = @{ value = $AutomationAzVersion }
        automationRunbooks = @{ value = @($automationRunbooks | ForEach-Object {
            @{
                name = $_.name
                sourceHash = $_.sourceHash
            }
        }) }
        vmStartScheduleEnabled = @{ value = $VmStartScheduleEnabled }
        vmStartScheduleStartTime = @{ value = $vmStartScheduleStartTime }
        vmStartScheduleTimeZone = @{ value = $VmStartScheduleTimeZone }
        rdpDeployerCleanupScheduleEnabled = @{ value = $RdpDeployerCleanupScheduleEnabled }
        rdpDeployerCleanupScheduleStartTime = @{ value = $rdpDeployerCleanupScheduleStartTime }
        rdpDeployerCleanupScheduleTimeZone = @{ value = $RdpDeployerCleanupScheduleTimeZone }
        privateAiWorkspacesOnly = @{ value = $PrivateAiWorkspacesOnly }
        logAnalyticsRetentionDays = @{ value = $LogAnalyticsRetentionDays }
        rdpAllowRules = @{ value = @($rdpAllowRules) }
        deployingObjectId = @{ value = $deployingObjectId }
        deployingPrincipalType = @{ value = ($accountType -eq 'servicePrincipal' ? 'ServicePrincipal' : 'User') }
        # Passes the original creation date so Bicep can preserve it on the createdDate tag
        # across redeployments. Empty string on first deploy; Bicep then defaults to utcNow().
        resourceCreatedDate = @{ value = $createdDateTagValue }
    }
}

$deploymentParameters | ConvertTo-Json -Depth 10 | Set-Content -Path $parameterFile -Encoding UTF8

Write-Task "Deploying enterprise AI Foundry stack for environment '$EnvironmentSuffix'..."
Write-Info "  Core RG    : $CoreResourceGroupName"
Write-Info "  Network RG : $NetworkResourceGroupName"
if (-not $WhatIf) {
    Write-Task 'Ensuring required resource groups exist...'
    az group create --name $CoreResourceGroupName --location $Location --output none
    az group create --name $NetworkResourceGroupName --location $Location --output none

    Write-Task 'Checking for stale Azure ML workspaces from previous failed deployments...'
    $armHeaders = Get-AzureArmHeaders -SubscriptionId $subscriptionId
    if ($null -eq $armHeaders) {
        Write-Error 'Unable to acquire an ARM access token for the active subscription/tenant context.'
        exit 1
    }
    $purgedWorkspaceNames = [System.Collections.Generic.List[string]]::new()

foreach ($workspaceName in @($hubName, $projectName)) {
    $getUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$CoreResourceGroupName/providers/Microsoft.MachineLearningServices/workspaces/${workspaceName}?api-version=$MlApiVersion"
    $workspaceProvisioningState = $null
    try {
        $wsResult = Invoke-RestMethod -Method GET -Uri $getUri -Headers $armHeaders -ErrorAction Stop
        $workspaceProvisioningState = $wsResult.properties.provisioningState
    } catch {
        $wsGetStatus = $null
        if ($_.Exception.Response) { $wsGetStatus = [int]$_.Exception.Response.StatusCode }
        if ($wsGetStatus -eq 404) {
            Write-Exists "  Workspace '$workspaceName' not found — fresh deploy, no purge needed."
        } else {
            Write-Info "  Warning: could not check workspace '$workspaceName' status (HTTP $wsGetStatus). Will attempt purge."
            $workspaceProvisioningState = 'Unknown'
        }
    }

    if ($workspaceProvisioningState -eq 'Succeeded') {
        Write-Exists "  Workspace '$workspaceName' is healthy (Succeeded) — skipping purge, Bicep will update in-place."
        continue
    }

    if ($null -eq $workspaceProvisioningState) {
        continue
    }

    Write-Needed "  Workspace '$workspaceName' is in state '$workspaceProvisioningState' — purging before redeploy."
    $deleteUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$CoreResourceGroupName/providers/Microsoft.MachineLearningServices/workspaces/$workspaceName`?api-version=$MlApiVersion&forcePurge=true"
    try {
        Invoke-RestMethod -Method DELETE -Uri $deleteUri -Headers $armHeaders -ErrorAction Stop | Out-Null
        Write-Exists "  Purged stale ML workspace '$workspaceName'."
        $purgedWorkspaceNames.Add($workspaceName)
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
        if ($statusCode -ne 404) {
            Write-Info "  Warning: could not purge workspace '$workspaceName': $($_.Exception.Message)"
        }
    }
}

if ($purgedWorkspaceNames.Count -gt 0) {
    Write-Task 'Waiting for purged workspaces to complete deletion...'
    $maxWaitSeconds = 120
    $pollIntervalSeconds = 10
    foreach ($workspaceName in $purgedWorkspaceNames) {
        $getUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$CoreResourceGroupName/providers/Microsoft.MachineLearningServices/workspaces/${workspaceName}?api-version=$MlApiVersion"
        $elapsed = 0
        while ($elapsed -lt $maxWaitSeconds) {
            try {
                Invoke-RestMethod -Method GET -Uri $getUri -Headers $armHeaders -ErrorAction Stop | Out-Null
                Write-Info "  Still deleting '$workspaceName' (${elapsed}s elapsed)..."
                Start-Sleep -Seconds $pollIntervalSeconds
                $elapsed += $pollIntervalSeconds
            } catch {
                $wsStatusCode = $null
                if ($_.Exception.Response) {
                    $wsStatusCode = [int]$_.Exception.Response.StatusCode
                }
                if ($wsStatusCode -eq 404) {
                    Write-Exists "  Workspace '$workspaceName' confirmed deleted."
                } else {
                    Write-Info "  Warning: could not confirm deletion of '$workspaceName' (HTTP $wsStatusCode). Proceeding anyway."
                }
                break
            }
        }
        if ($elapsed -ge $maxWaitSeconds) {
            Write-Info "  Timed out waiting for '$workspaceName' deletion after ${maxWaitSeconds}s. Proceeding anyway."
        }
    }
}

Write-Task 'Checking for soft-deleted Key Vault...'
$deletedKvJson = az keyvault list-deleted `
    --resource-type vault `
    --query "[?name=='$keyVaultName']" `
    --output json 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($deletedKvJson)) {
    $deletedKvVaults = @($deletedKvJson | ConvertFrom-Json)
    if ($deletedKvVaults.Count -gt 0) {
        Write-Needed "  Purging soft-deleted Key Vault '$keyVaultName'..."
        az keyvault purge --name $keyVaultName --location $Location --output none
        if ($LASTEXITCODE -eq 0) {
            Write-Exists "  Purged soft-deleted Key Vault '$keyVaultName'."
        } else {
            Write-Info "  Warning: could not purge Key Vault '$keyVaultName'. Deployment may fail with ConflictError."
        }
    } else {
        Write-Exists "  No soft-deleted Key Vault found — fresh deploy."
    }
} else {
    Write-Exists "  No soft-deleted Key Vault found — fresh deploy."
}

Write-Task 'Checking for soft-deleted Cognitive Services account...'
$deletedOaiJson = az cognitiveservices account list-deleted `
    --query "[?name=='$openAiAccountName' && location=='$Location']" `
    --output json 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($deletedOaiJson)) {
    $deletedOaiAccounts = @($deletedOaiJson | ConvertFrom-Json)
    if ($deletedOaiAccounts.Count -gt 0) {
        Write-Needed "  Purging soft-deleted OpenAI account '$openAiAccountName'..."
        az cognitiveservices account purge `
            --location $Location `
            --resource-group $CoreResourceGroupName `
            --name $openAiAccountName `
            --output none
        if ($LASTEXITCODE -eq 0) {
            Write-Exists "  Purged soft-deleted OpenAI account '$openAiAccountName'."
        } else {
            Write-Info "  Warning: could not purge OpenAI account '$openAiAccountName'. Deployment may fail with FlagMustBeSetForRestore error."
        }
    } else {
        Write-Exists "  No soft-deleted OpenAI account found — fresh deploy."
    }
} else {
    Write-Exists "  No soft-deleted OpenAI account found — fresh deploy."
}

Write-Task 'Checking for stale OpenAI diagnostic settings from previous deployments...'
$oaiExistsJson = az cognitiveservices account show `
    --resource-group $CoreResourceGroupName `
    --name $openAiAccountName `
    --query id `
    --output json 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($oaiExistsJson)) {
    $staleDiagSettings = @('send-audit-to-law')
    foreach ($staleSetting in $staleDiagSettings) {
        $staleSettingJson = az monitor diagnostic-settings show `
            --resource $openAiAccountName `
            --resource-group $CoreResourceGroupName `
            --resource-type 'Microsoft.CognitiveServices/accounts' `
            --name $staleSetting `
            --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($staleSettingJson)) {
            Write-Needed "  Removing stale diagnostic setting '$staleSetting' from OpenAI account '$openAiAccountName'..."
            az monitor diagnostic-settings delete `
                --resource $openAiAccountName `
                --resource-group $CoreResourceGroupName `
                --resource-type 'Microsoft.CognitiveServices/accounts' `
                --name $staleSetting `
                --output none
            if ($LASTEXITCODE -eq 0) {
                Write-Exists "  Removed stale diagnostic setting '$staleSetting'."
            } else {
                Write-Info "  Warning: could not remove diagnostic setting '$staleSetting'. Deployment may fail with Conflict error."
            }
        } else {
            Write-Exists "  Stale diagnostic setting '$staleSetting' not found — no cleanup needed."
        }
    }
} else {
    Write-Exists "  OpenAI account '$openAiAccountName' does not exist yet — no diagnostic cleanup needed."
}

Write-Task 'Checking for VM Spot priority conflict...'
$vmResourceListJson = az resource list `
    --resource-group $CoreResourceGroupName `
    --resource-type 'Microsoft.Compute/virtualMachines' `
    --query "[?name=='$vmName'].id" `
    --output json 2>$null
$vmExists = $false
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($vmResourceListJson)) {
    $vmIds = @($vmResourceListJson | ConvertFrom-Json)
    $vmExists = $vmIds.Count -gt 0
}

if ($vmExists) {
    $existingPriorityTsv = az resource show `
        --resource-group $CoreResourceGroupName `
        --name $vmName `
        --resource-type 'Microsoft.Compute/virtualMachines' `
        --query 'properties.priority' `
        --output tsv 2>$null

    if ($LASTEXITCODE -ne 0) {
            Write-Info "  VM '$vmName' exists but priority could not be read — skipping pre-deploy deletion."
    } else {
        $existingIsSpot = ($existingPriorityTsv -eq 'Spot')
        if ($existingPriorityTsv -eq 'None') { $existingIsSpot = $false }

        if ($VmUseSpot -ne $existingIsSpot) {
            $changeDesc = if ($VmUseSpot) { 'Regular -> Spot' } else { 'Spot -> Regular' }
            Write-Needed "  Priority change detected ($changeDesc) — deleting VM '$vmName' and its OS disk so Bicep can recreate with correct priority..."
            az vm delete `
                --resource-group $CoreResourceGroupName `
                --name $vmName `
                --yes `
                --output none
            if ($LASTEXITCODE -eq 0) {
                Write-Exists "  VM '$vmName' deleted."
            } else {
                Write-Info "  Warning: VM deletion may have failed. Deployment will attempt to continue."
            }
            $osDiskName = "$vmName-osdisk"
            $diskExists = az disk show `
                --resource-group $CoreResourceGroupName `
                --name $osDiskName `
                --query id `
                --output tsv 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($diskExists)) {
                Write-Needed "  Deleting orphaned OS disk '$osDiskName'..."
                az disk delete `
                    --resource-group $CoreResourceGroupName `
                    --name $osDiskName `
                    --yes `
                    --output none
                if ($LASTEXITCODE -eq 0) {
                    Write-Exists "  OS disk '$osDiskName' deleted."
                } else {
                    Write-Info "  Warning: OS disk deletion may have failed. Deployment will attempt to continue."
                }
            }
        } else {
            $priorityDisplay = if ($existingIsSpot) { 'Spot' } else { 'Regular' }
            Write-Exists "  VM '$vmName' has correct priority ($priorityDisplay) — no action needed."
        }
    }
} else {
    Write-Exists "  VM '$vmName' does not exist yet — fresh deploy."
}

# ----------------------------------------------------------------
# Deployment-flag removal
# ----------------------------------------------------------------
# Each variables/<env>.yaml deploy* flag is authoritative: true deploys and keeps the component
# current, false removes it if a previous run created it. Only optional components have a flag.
# The following are deliberately NOT removable because they hold deployment state or every other
# component depends on them: resource groups, the virtual network and subnets, private DNS zones
# and VNet links, Key Vault and its private endpoint (holds all deployment secrets), Azure OpenAI
# and its private endpoint (holds the model deployments), and the hub/VM managed identities.
Write-Task 'Applying component deployment flags (removing disabled components)...'

$removeResourceById = {
    param([string]$ResourceId, [string]$Description)

    az resource show --ids $ResourceId --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    Write-Needed "  Removing $Description (deployment flag is false)..."
    az resource delete --ids $ResourceId --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Exists "  Removed $Description."
    } else {
        Write-Info "  Warning: could not remove $Description. Remove it manually and rerun."
    }
    return $true
}

$coreScopeId = "/subscriptions/$subscriptionId/resourceGroups/$CoreResourceGroupName"
$networkScopeId = "/subscriptions/$subscriptionId/resourceGroups/$NetworkResourceGroupName"

if (-not $DeployAutomation) {
    # Runbooks, schedules, and job schedules are children of the Automation Account and are
    # removed with it. The automation identity exists only to run those runbooks.
    & $removeResourceById "$coreScopeId/providers/Microsoft.Automation/automationAccounts/$automationAccountName" "Automation Account '$automationAccountName'" | Out-Null
    & $removeResourceById "$coreScopeId/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$automationManagedIdentityName" "Automation managed identity '$automationManagedIdentityName'" | Out-Null
}

if (-not $DeployVm) {
    # Order matters: the schedule and VM must go before the NIC, and the NIC before the public IP
    # and NSG. The OS disk survives 'az vm delete', so it is removed explicitly.
    & $removeResourceById "$coreScopeId/providers/Microsoft.DevTestLab/schedules/shutdown-computevm-$vmName" "VM auto-shutdown schedule for '$vmName'" | Out-Null
    & $removeResourceById "$coreScopeId/providers/Microsoft.Compute/virtualMachines/$vmName" "jumpbox VM '$vmName'" | Out-Null
    & $removeResourceById "$coreScopeId/providers/Microsoft.Compute/disks/$vmName-osdisk" "VM OS disk '$vmName-osdisk'" | Out-Null
    & $removeResourceById "$networkScopeId/providers/Microsoft.Network/networkInterfaces/$vmName-nic" "VM NIC '$vmName-nic'" | Out-Null
    & $removeResourceById "$networkScopeId/providers/Microsoft.Network/publicIPAddresses/$vmName-pip" "VM public IP '$vmName-pip'" | Out-Null
    & $removeResourceById "$networkScopeId/providers/Microsoft.Network/networkSecurityGroups/$vmName-nsg" "VM NSG '$vmName-nsg'" | Out-Null
}

if (-not $DeployAiFoundry) {
    # The project is a child workspace of the hub, so it must be deleted first.
    foreach ($workspaceToRemove in @($projectName, $hubName)) {
        $workspaceUri = "https://management.azure.com$coreScopeId/providers/Microsoft.MachineLearningServices/workspaces/$workspaceToRemove`?api-version=$MlApiVersion&forcePurge=true"
        try {
            Invoke-RestMethod -Method DELETE -Uri $workspaceUri -Headers $armHeaders -ErrorAction Stop | Out-Null
            Write-Exists "  Removed AI workspace '$workspaceToRemove' (deployment flag is false)."
        } catch {
            $removeStatusCode = $null
            if ($_.Exception.Response) { $removeStatusCode = [int]$_.Exception.Response.StatusCode }
            if ($removeStatusCode -ne 404) {
                Write-Info "  Warning: could not remove AI workspace '$workspaceToRemove': $($_.Exception.Message)"
            }
        }
    }
    & $removeResourceById "$networkScopeId/providers/Microsoft.Network/privateEndpoints/$hubName-pe" "AI Hub private endpoint '$hubName-pe'" | Out-Null
}

if (-not $DeployStorage) {
    # The private endpoint references the storage account, so it must be removed first.
    & $removeResourceById "$networkScopeId/providers/Microsoft.Network/privateEndpoints/$storageAccountName-blob-pe" "Storage private endpoint '$storageAccountName-blob-pe'" | Out-Null
    & $removeResourceById "$coreScopeId/providers/Microsoft.Storage/storageAccounts/$storageAccountName" "Storage account '$storageAccountName'" | Out-Null
}

if (-not $DeployLogAnalytics) {
    # Diagnostic settings pointing at the workspace must be removed before the workspace itself.
    $diagnosticTargetIds = @(
        "$coreScopeId/providers/Microsoft.CognitiveServices/accounts/$openAiAccountName"
        "$coreScopeId/providers/Microsoft.KeyVault/vaults/$keyVaultName"
        "$coreScopeId/providers/Microsoft.Storage/storageAccounts/$storageAccountName"
        "$coreScopeId/providers/Microsoft.MachineLearningServices/workspaces/$hubName"
    )
    foreach ($diagnosticTargetId in $diagnosticTargetIds) {
        $diagnosticListJson = az monitor diagnostic-settings list --resource $diagnosticTargetId --output json 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($diagnosticListJson)) {
            continue
        }
        $diagnosticSettings = @(($diagnosticListJson | ConvertFrom-Json).value)
        foreach ($diagnosticSetting in $diagnosticSettings) {
            if ([string]::IsNullOrWhiteSpace($diagnosticSetting.name)) { continue }
            Write-Needed "  Removing diagnostic setting '$($diagnosticSetting.name)' (deployLogAnalytics is false)..."
            az monitor diagnostic-settings delete --resource $diagnosticTargetId --name $diagnosticSetting.name --output none 2>$null
        }
    }
    & $removeResourceById "$coreScopeId/providers/Microsoft.OperationalInsights/workspaces/$LogAnalyticsWorkspaceName" "Log Analytics workspace '$LogAnalyticsWorkspaceName'" | Out-Null
}

$identityNamesForRoleCleanup = @($hubManagedIdentityName, $vmManagedIdentityName, $legacyManagedIdentityName)
$miRoleGuids = @(
    'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
    '4633458b-17de-408a-b874-0445c86b69e6'
    '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
)
foreach ($identityNameForRoleCleanup in $identityNamesForRoleCleanup) {
    $miPrincipalId = az identity show `
        --resource-group $CoreResourceGroupName `
        --name $identityNameForRoleCleanup `
        --query principalId `
        --output tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($miPrincipalId)) {
        continue
    }

    Write-Task "Removing stale role assignments for managed identity '$identityNameForRoleCleanup' before deployment..."
    foreach ($roleGuid in $miRoleGuids) {
        $existingAssignmentsJson = az role assignment list `
            --assignee $miPrincipalId `
            --role $roleGuid `
            --resource-group $CoreResourceGroupName `
            --query '[].id' `
            --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($existingAssignmentsJson)) {
            $assignmentIds = $existingAssignmentsJson | ConvertFrom-Json
            foreach ($assignmentId in $assignmentIds) {
                if (-not [string]::IsNullOrWhiteSpace($assignmentId)) {
                    az role assignment delete --ids $assignmentId --output none
                    if ($LASTEXITCODE -eq 0) {
                        Write-Exists "  Removed role '$roleGuid' from '$identityNameForRoleCleanup'."
                    }
                }
            }
        }
    }
    }

    # Actor role assignments are owned solely by actorroles.bicep / networkroles.bicep. Earlier
    # revisions created some of the same role/principal/scope pairs from other modules with a
    # different deterministic name, which makes ARM fail with RoleAssignmentExists. Remove any
    # existing assignment for a managed role at (or below) the environment resource groups so the
    # deployment can recreate it under the name the templates own.
    $actorRoleGuids = @(
        '00482a5a-887f-4fb3-b363-3b7fe8e74483'  # Key Vault Administrator
        'a001fd3d-188f-4b5d-821b-7da978bf7442'  # Cognitive Services OpenAI Contributor
        '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68'  # Cognitive Services Contributor
        'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'  # Storage Blob Data Owner
        '17d1049b-9a84-46fb-8f53-869881c3d3ab'  # Storage Account Contributor
        'b78c5d69-af96-48a3-bf8d-a8b4d589de94'  # Azure AI Administrator
        '1c0163c0-47e6-4577-8991-ea5c82e286e4'  # Virtual Machine Administrator Login
        '92aaf0da-9dab-42b6-94a3-d43ce8d16293'  # Log Analytics Contributor
        '749f88d5-cbae-40b8-bcfc-e573ddc772fa'  # Monitoring Contributor
        '4633458b-17de-408a-b874-0445c86b69e6'  # Key Vault Secrets User
        'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'  # Key Vault Secrets Officer
        '21090545-7ca7-4776-b22c-e363652d74d2'  # Key Vault Reader
        '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'  # Cognitive Services OpenAI User
        'a97b65f3-24c7-4388-baec-2e87135dc908'  # Cognitive Services User
        'ba92f5b4-2d11-453d-a403-e96b0029c9fe'  # Storage Blob Data Contributor
        '64702f94-c441-49e6-a78b-ef80e0188fee'  # Azure AI Developer
        'f6c7c914-8db3-469d-8ca1-694a8f32e121'  # AzureML Data Scientist
        'fb879df8-f326-4884-b1cf-06f3ad86be52'  # Virtual Machine User Login
        '73c42c96-874c-492b-b04d-ab87d138a893'  # Log Analytics Reader
        '43d0d8ad-25c7-4714-9337-8ba259a9fe05'  # Monitoring Reader
        'b24988ac-6180-42a0-ab88-20f7382dd24c'  # Contributor
        '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'  # User Access Administrator
        'acdd72a7-3385-48ef-bd42-f606fba81ae7'  # Reader
    )
    $managedScopePrefixes = @($coreScopeId.ToLowerInvariant(), $networkScopeId.ToLowerInvariant())
    $actorPrincipalIds = @(@($AdminActors + $UserActors) |
        ForEach-Object { [string]$_.objectId } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique)

    foreach ($actorPrincipalId in $actorPrincipalIds) {
        $actorAssignmentsJson = az role assignment list `
            --all `
            --assignee $actorPrincipalId `
            --query '[].{id:id, scope:scope, role:roleDefinitionId}' `
            --output json 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($actorAssignmentsJson)) {
            continue
        }

        $staleActorAssignments = @(@($actorAssignmentsJson | ConvertFrom-Json) | Where-Object {
            $assignmentScope = ([string]$_.scope).ToLowerInvariant()
            $assignmentRoleGuid = ([string]$_.role -split '/')[-1]
            ($managedScopePrefixes | Where-Object { $assignmentScope.StartsWith($_) }) -and
            ($actorRoleGuids -contains $assignmentRoleGuid)
        })

        if ($staleActorAssignments.Count -eq 0) {
            continue
        }

        Write-Task "Removing stale role assignments for actor '$actorPrincipalId' before deployment..."
        foreach ($staleActorAssignment in $staleActorAssignments) {
            az role assignment delete --ids $staleActorAssignment.id --output none
            if ($LASTEXITCODE -eq 0) {
                Write-Exists "  Removed role '$((([string]$staleActorAssignment.role) -split '/')[-1])' at '$($staleActorAssignment.scope)'."
            }
        }
    }
} else {
    Write-Info 'Preview mode: skipping resource-group creation and destructive stale-resource cleanup.'
}

if ($WhatIf) {
    Write-Task "Running subscription what-if '$deploymentName' in location '$Location'..."
    az deployment sub what-if `
        --name $deploymentName `
        --subscription $subscriptionId `
        --location $Location `
        --template-file $templateFile `
        --parameters "@$parameterFile" `
        --output table
} else {
    $phaseWatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Task "Running subscription deployment '$deploymentName' in location '$Location'..."
    az deployment sub create `
        --name $deploymentName `
        --subscription $subscriptionId `
        --location $Location `
        --template-file $templateFile `
        --parameters "@$parameterFile" `
        --output table
}

if ($LASTEXITCODE -ne 0) {
    Write-Needed 'Deployment failed. Fetching deployment error details...'
    $deploymentExists = az deployment sub list --subscription $subscriptionId --query "[?name=='$deploymentName'] | length(@)" --output tsv 2>$null
    if ($deploymentExists -ne '0') {
        az deployment sub show --name $deploymentName --subscription $subscriptionId --query properties.error --output jsonc
    } else {
        Write-Info 'Deployment did not reach Azure Resource Manager. No deployment record was created.'
    }
    Remove-Item $parameterFile -Force -ErrorAction SilentlyContinue
    Write-Error "Deployment failed. Aborting app packaging."
    exit 1
}

if ($WhatIf) {
    Remove-Item $parameterFile -Force -ErrorAction SilentlyContinue
    Write-Exists 'What-if completed. Skipping runbook publication, secret sync, and app packaging.'
    exit 0
}
Write-Info "[Bicep] completed in $($phaseWatch.Elapsed.ToString('mm\:ss'))"
$phaseWatch.Restart()

$deploymentOutputs = $null
$deploymentOutputs = Get-SubscriptionDeploymentOutputs `
    -SubscriptionId $subscriptionId `
    -DeploymentName $deploymentName
if ($null -eq $deploymentOutputs) {
    Write-Info 'Warning: could not read deployment outputs. Falling back to derived defaults.'
}

if ($AutomationEnabled) {
    $automationIdentityClientId = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'automationManagedIdentityClientId').Trim()
    if ([string]::IsNullOrWhiteSpace($automationIdentityClientId)) {
        $automationIdentityClientIdRaw = az identity show `
            --resource-group $CoreResourceGroupName `
            --name $automationManagedIdentityName `
            --query clientId `
            --output tsv 2>$null
        $automationIdentityClientId = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($automationIdentityClientIdRaw)) {
            $automationIdentityClientIdRaw.Trim()
        } else {
            ''
        }
    }
    if ([string]::IsNullOrWhiteSpace($automationIdentityClientId)) {
        throw "Could not resolve the client ID for Automation identity '$automationManagedIdentityName'."
    }

    Publish-AutomationRunbooks `
        -SubscriptionId $subscriptionId `
        -ResourceGroupName $CoreResourceGroupName `
        -AutomationAccountName $automationAccountName `
        -Runbooks $automationRunbooks

    if ($VmStartScheduleEnabled) {
        $automationJobScheduleName = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'automationJobScheduleName').Trim()
        if ([string]::IsNullOrWhiteSpace($automationJobScheduleName)) {
            throw 'The deployment did not return the deterministic Automation job schedule name.'
        }
        Set-AutomationJobSchedule `
            -SubscriptionId $subscriptionId `
            -ResourceGroupName $CoreResourceGroupName `
            -AutomationAccountName $automationAccountName `
            -JobScheduleName $automationJobScheduleName `
            -ScheduleName $vmStartScheduleName `
            -RunbookName 'start-vm' `
            -RunbookParameters @{
                automationIdentityClientId = $automationIdentityClientId
                resourceGroupName = $CoreResourceGroupName
                subscriptionId = $subscriptionId
                vmName = $vmName
            }
    }
    if ($RdpDeployerCleanupScheduleEnabled) {
        $rdpCleanupJobScheduleName = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'rdpDeployerCleanupJobScheduleName').Trim()
        if ([string]::IsNullOrWhiteSpace($rdpCleanupJobScheduleName)) {
            throw 'The deployment did not return the deterministic RDP cleanup job schedule name.'
        }
        Set-AutomationJobSchedule `
            -SubscriptionId $subscriptionId `
            -ResourceGroupName $CoreResourceGroupName `
            -AutomationAccountName $automationAccountName `
            -JobScheduleName $rdpCleanupJobScheduleName `
            -ScheduleName $rdpDeployerCleanupScheduleName `
            -RunbookName 'delete-rdp-deployer-rule' `
            -RunbookParameters @{
                automationIdentityClientId = $automationIdentityClientId
                networkSecurityGroupName = "$vmName-nsg"
                resourceGroupName = $NetworkResourceGroupName
                subscriptionId = $subscriptionId
            }
    }
    Write-Info "[Automation runbooks] completed in $($phaseWatch.Elapsed.ToString('mm\:ss'))"
    $phaseWatch.Restart()
}

$legacyIdentityId = az identity show `
    --resource-group $CoreResourceGroupName `
    --name $legacyManagedIdentityName `
    --query id `
    --output tsv 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($legacyIdentityId)) {
    Write-Task "Removing retired shared managed identity '$legacyManagedIdentityName'..."
    az identity delete `
        --resource-group $CoreResourceGroupName `
        --name $legacyManagedIdentityName `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to remove retired shared managed identity '$legacyManagedIdentityName'."
        exit 1
    }
    Write-Exists "  Retired shared managed identity '$legacyManagedIdentityName' removed."
}

$keyVaultUrl = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'keyVaultUri').Trim()
if ([string]::IsNullOrWhiteSpace($keyVaultUrl)) {
    $keyVaultUrl = "https://${keyVaultName}.vault.azure.net/"
}

$openAiEndpoint = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'openAiEndpoint').Trim()
if ([string]::IsNullOrWhiteSpace($openAiEndpoint)) {
    $openAiEndpoint = "https://${openAiAccountName}.openai.azure.com/"
}
$openAiDeployment = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'deploymentName').Trim()
$openAiSecondaryDeployment = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'secondaryDeploymentName').Trim()
$managedIdentityClientId = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'vmManagedIdentityClientId').Trim()
$logAnalyticsWorkspaceId = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'logAnalyticsWorkspaceId').Trim()
$logAnalyticsWorkspaceName = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'logAnalyticsWorkspaceName').Trim()
$vmPublicIpAddress = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'vmPublicIpAddress').Trim()
if ([string]::IsNullOrWhiteSpace($managedIdentityClientId)) {
    $managedIdentityClientIdRaw = az identity show --resource-group $CoreResourceGroupName --name $vmManagedIdentityName --query clientId --output tsv 2>$null
    $managedIdentityClientId = if (-not [string]::IsNullOrWhiteSpace($managedIdentityClientIdRaw)) { $managedIdentityClientIdRaw.Trim() } else { '' }
}

if ([string]::IsNullOrWhiteSpace($vmPublicIpAddress)) {
    $vmPublicIpAddressRaw = az network public-ip show `
        --resource-group $NetworkResourceGroupName `
        --name "$vmName-pip" `
        --query ipAddress `
        --output tsv 2>$null
    $vmPublicIpAddress = if (-not [string]::IsNullOrWhiteSpace($vmPublicIpAddressRaw)) { $vmPublicIpAddressRaw.Trim() } else { '<query Azure portal>' }
}

if ([string]::IsNullOrWhiteSpace($openAiDeployment)) {
    $openAiDeployment = $ModelDeploymentName
}
if ([string]::IsNullOrWhiteSpace($openAiSecondaryDeployment)) {
    $openAiSecondaryDeployment = $SecondaryModelDeploymentName
}

if ([string]::IsNullOrWhiteSpace($logAnalyticsWorkspaceName)) {
    $logAnalyticsWorkspaceName = "law-$BaseName-$EnvironmentSuffix-$NameSuffix"
}

if ([string]::IsNullOrWhiteSpace($logAnalyticsWorkspaceId)) {
    $logAnalyticsWorkspaceIdRaw = az monitor log-analytics workspace show `
        --resource-group $CoreResourceGroupName `
        --workspace-name $logAnalyticsWorkspaceName `
        --query id `
        --output tsv 2>$null
    $logAnalyticsWorkspaceId = if (-not [string]::IsNullOrWhiteSpace($logAnalyticsWorkspaceIdRaw)) { $logAnalyticsWorkspaceIdRaw.Trim() } else { '' }
}

try {
    if ($DeployLogAnalytics -and -not [string]::IsNullOrWhiteSpace($logAnalyticsWorkspaceName)) {
        Set-LogAnalyticsDailyQuota `
            -ResourceGroupName $CoreResourceGroupName `
            -WorkspaceName $logAnalyticsWorkspaceName `
            -DailyQuotaGb $LogAnalyticsDailyQuotaGb
    }

    if ($DeployLogAnalytics -and $EnableAuditDiagnostics -and -not [string]::IsNullOrWhiteSpace($logAnalyticsWorkspaceId)) {
        Set-AuditDiagnosticsForImportantResources `
            -CoreResourceGroupName $CoreResourceGroupName `
            -NetworkResourceGroupName $NetworkResourceGroupName `
            -WorkspaceId $logAnalyticsWorkspaceId
    }
} catch {
    Write-Info "  Warning: post-deploy diagnostics configuration encountered an error (non-fatal): $_"
}

Write-Task 'Syncing Key Vault secrets through Azure Resource Manager...'
$keyVaultResourceId = "/subscriptions/$subscriptionId/resourceGroups/$CoreResourceGroupName/providers/Microsoft.KeyVault/vaults/$keyVaultName"
$secretSyncFailures = @()
if (-not (Sync-KeyVaultSecretValue -VaultResourceId $keyVaultResourceId -SecretName 'openai-endpoint' -SecretValue $openAiEndpoint)) {
    $secretSyncFailures += 'openai-endpoint'
}
if (-not (Sync-KeyVaultSecretValue -VaultResourceId $keyVaultResourceId -SecretName 'openai-deployment' -SecretValue $openAiDeployment)) {
    $secretSyncFailures += 'openai-deployment'
}
if (-not (Sync-KeyVaultSecretValue -VaultResourceId $keyVaultResourceId -SecretName 'openai-secondary-deployment' -SecretValue $openAiSecondaryDeployment)) {
    $secretSyncFailures += 'openai-secondary-deployment'
}
if ($preserveExistingVmPassword) {
    Write-Info "  Skipping vm-admin-password sync because the existing VM password is being preserved."
} elseif (-not [string]::IsNullOrWhiteSpace($VmAdminPassword)) {
    if (-not (Sync-KeyVaultSecretValue -VaultResourceId $keyVaultResourceId -SecretName 'vm-admin-password' -SecretValue $VmAdminPassword)) {
        $secretSyncFailures += 'vm-admin-password'
    }
} else {
    Write-Info "  Skipping vm-admin-password sync because the password is not available."
}
if (-not (Sync-KeyVaultSecretValue -VaultResourceId $keyVaultResourceId -SecretName 'keyvault-url' -SecretValue $keyVaultUrl)) {
    $secretSyncFailures += 'keyvault-url'
}
if (-not [string]::IsNullOrWhiteSpace($managedIdentityClientId)) {
    if (-not (Sync-KeyVaultSecretValue -VaultResourceId $keyVaultResourceId -SecretName 'managed-identity-client-id' -SecretValue $managedIdentityClientId)) {
        $secretSyncFailures += 'managed-identity-client-id'
    }
}
$openAiApiVersion = if (-not [string]::IsNullOrWhiteSpace($config.openaiApiVersion)) { $config.openaiApiVersion } else { '2025-01-01-preview' }
if (-not (Sync-KeyVaultSecretValue -VaultResourceId $keyVaultResourceId -SecretName 'openai-api-version' -SecretValue $openAiApiVersion)) {
    $secretSyncFailures += 'openai-api-version'
}

if ($secretSyncFailures.Count -gt 0) {
    Write-Error "Failed to sync required Key Vault secrets: $($secretSyncFailures -join ', ')."
    exit 1
}

# Compute and store a config-version hash so first-run.ps1 can detect stale .env files.
# The hash covers the values that, if changed, should trigger a .env refresh on the VM.
$configVersionInput = "$openAiEndpoint|$openAiDeployment|$openAiSecondaryDeployment|$openAiApiVersion|$managedIdentityClientId"
$configVersionHash  = ([System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($configVersionInput)
    )
) -replace '-', '').ToLowerInvariant().Substring(0, 16)
$null = Sync-KeyVaultSecretValue -VaultResourceId $keyVaultResourceId -SecretName 'config-version' -SecretValue $configVersionHash
Write-Exists "  Config version hash stored: $configVersionHash"

Write-Task 'Generating first-run.ps1 for VM...'
Write-Info "[Secrets sync] completed in $($phaseWatch.Elapsed.ToString('mm\:ss'))"
$phaseWatch.Restart()
$firstRunFile = Join-Path $tempDir "first-run-$EnvironmentSuffix.$PID.ps1"

$firstAdminObjectId = if ($AdminObjectIds.Count -gt 0) { $AdminObjectIds[0] } else { '' }

# Values are substituted directly into the script at deploy time so the VM
# does not need any parameters — it is self-contained.
$firstRunContent = @"
`$ErrorActionPreference = 'Stop'

`$KeyVaultName  = '$keyVaultName'
`$KeyVaultUrl   = '$keyVaultUrl'
`$MiClientId    = '$managedIdentityClientId'
`$AdminObjectId = '$firstAdminObjectId'
`$AdminUpn      = '$adminUpn'
`$TenantId      = '$tenantId'
`$AppDir        = 'C:\ChatApp'
`$EnvFile       = "`$AppDir\.env"

# ----------------------------------------------------------------
# If .env already exists, check whether the deployment config has
# changed since it was written (config-version secret in Key Vault).
# If the version matches, skip auth and re-sync — just launch.
# If the version has changed, delete .env so it is regenerated below.
# ----------------------------------------------------------------
if (Test-Path `$EnvFile) {
    `$storedVersion = ''
    try {
        `$storedVersion = (Get-Content `$EnvFile | Where-Object { `$_ -match '^CONFIG_VERSION=' }) -replace '^CONFIG_VERSION=', ''
    } catch { }

    `$kvVersion = (az keyvault secret show --vault-name `$KeyVaultName --name 'config-version' --query value --output tsv 2>`$null).Trim()

    if (-not [string]::IsNullOrWhiteSpace(`$kvVersion) -and `$storedVersion -eq `$kvVersion) {
        Write-Host 'Configuration is current — launching chat app...' -ForegroundColor Green
        & "`$AppDir\.venv\Scripts\python.exe" "`$AppDir\chat.py"
        exit 0
    } elseif (-not [string]::IsNullOrWhiteSpace(`$kvVersion) -and `$storedVersion -ne `$kvVersion) {
        Write-Host 'Deployment configuration has changed — refreshing .env...' -ForegroundColor Yellow
        Remove-Item `$EnvFile -Force -ErrorAction SilentlyContinue
    } else {
        # Could not read config-version from KV (network/auth issue) — keep existing .env.
        Write-Host 'Configuration found (could not verify version) — launching chat app...' -ForegroundColor DarkGray
        & "`$AppDir\.venv\Scripts\python.exe" "`$AppDir\chat.py"
        exit 0
    }
}

# ----------------------------------------------------------------
# First run — authenticate with Entra ID and pull secrets from KV.
# ----------------------------------------------------------------
Write-Host ''
Write-Host '  =================================================================' -ForegroundColor Cyan
Write-Host '  Enterprise AI Chat — First-time Setup' -ForegroundColor Cyan
Write-Host '  =================================================================' -ForegroundColor Cyan
Write-Host ''

# Check whether an existing Azure CLI session for the correct tenant is cached.
`$needsLogin = `$true
try {
    `$ctxJson = az account show --output json 2>`$null
    if (`$LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(`$ctxJson)) {
        `$acct = `$ctxJson | ConvertFrom-Json
        if (`$acct.tenantId -eq `$TenantId) {
            `$needsLogin = `$false
            Write-Host "  Existing Azure session detected: `$(`$acct.user.name)" -ForegroundColor Green
        }
    }
} catch { }

if (`$needsLogin) {
    Write-Host '  You must sign in to Azure to fetch your chat app configuration.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Please sign in with the following account:' -ForegroundColor White
    Write-Host ''
    Write-Host "    Account   : `$AdminUpn" -ForegroundColor Cyan
    Write-Host "    Object ID : `$AdminObjectId" -ForegroundColor DarkGray
    Write-Host "    Tenant ID : `$TenantId" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  A browser window or device-code prompt will appear. Follow the instructions.' -ForegroundColor White
    Write-Host ''

    az login --use-device-code --tenant `$TenantId --allow-no-subscriptions
    if (`$LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host '  Login failed. Please try again.' -ForegroundColor Red
        Read-Host '  Press Enter to exit'
        exit 1
    }
    Write-Host '  Login successful.' -ForegroundColor Green
}

# ----------------------------------------------------------------
# Read all secrets from Key Vault into local variables.
# ----------------------------------------------------------------
Write-Host ''
Write-Host '  Reading configuration from Key Vault...' -ForegroundColor Blue

`$endpoint   = (az keyvault secret show --vault-name `$KeyVaultName --name 'openai-endpoint'             --query value --output tsv 2>`$null).Trim()
`$deployment = (az keyvault secret show --vault-name `$KeyVaultName --name 'openai-deployment'           --query value --output tsv 2>`$null).Trim()
`$secondary  = (az keyvault secret show --vault-name `$KeyVaultName --name 'openai-secondary-deployment' --query value --output tsv 2>`$null).Trim()
`$apiVersion = (az keyvault secret show --vault-name `$KeyVaultName --name 'openai-api-version'          --query value --output tsv 2>`$null).Trim()

if ([string]::IsNullOrWhiteSpace(`$endpoint) -or [string]::IsNullOrWhiteSpace(`$deployment)) {
    Write-Host ''
    Write-Host '  Error: could not read required secrets from Key Vault.' -ForegroundColor Red
    Write-Host '  Ensure your account has the Key Vault Secrets User role and retry.' -ForegroundColor Red
    Read-Host '  Press Enter to exit'
    exit 1
}

# ----------------------------------------------------------------
# Write .env — only occurs on first run or after manual deletion.
# To change any value, edit C:\ChatApp\.env directly; this script
# will NOT overwrite an existing .env file.
# ----------------------------------------------------------------
`$configVersion = (az keyvault secret show --vault-name `$KeyVaultName --name 'config-version' --query value --output tsv 2>`$null).Trim()

`$lines = @(
    "AZURE_KEY_VAULT_URL=`$KeyVaultUrl",
    "AZURE_CLIENT_ID=`$MiClientId",
    "AZURE_OPENAI_ENDPOINT=`$endpoint",
    "AZURE_OPENAI_DEPLOYMENT=`$deployment"
)
if (-not [string]::IsNullOrWhiteSpace(`$secondary))     { `$lines += "AZURE_OPENAI_SECONDARY_DEPLOYMENT=`$secondary" }
if (-not [string]::IsNullOrWhiteSpace(`$apiVersion))    { `$lines += "AZURE_OPENAI_API_VERSION=`$apiVersion" }
if (-not [string]::IsNullOrWhiteSpace(`$configVersion)) { `$lines += "CONFIG_VERSION=`$configVersion" }

Set-Content -Path `$EnvFile -Value (`$lines -join [System.Environment]::NewLine) -Encoding UTF8
Write-Host ''
Write-Host '  .env created successfully.' -ForegroundColor Green
Write-Host ''

# ----------------------------------------------------------------
# Launch the chat app.
# ----------------------------------------------------------------
Write-Host '  Starting chat app...' -ForegroundColor Cyan
Write-Host ''
& "`$AppDir\.venv\Scripts\python.exe" "`$AppDir\chat.py"
"@

Set-Content -Path $firstRunFile -Value $firstRunContent -Encoding UTF8
Write-Info "  Generated first-run.ps1: $firstRunFile"

Remove-Item $parameterFile -Force -ErrorAction SilentlyContinue

$appDirPath = Join-Path $scriptRoot '..\app'
if (-not (Test-Path $appDirPath)) {
    throw "Required application directory not found: $appDirPath"
}

$setupScriptPath = Join-Path $scriptRoot 'setup.ps1'
if (-not (Test-Path $setupScriptPath)) {
    throw "Required setup script not found: $setupScriptPath"
}

$appDir      = Resolve-Path $appDirPath
$setupScript = Resolve-Path $setupScriptPath

$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hashInputFiles = @(
    (Join-Path $appDir 'chat.py'),
    (Join-Path $appDir 'test.py'),
    (Join-Path $appDir 'requirements.txt'),
    $setupScript,
    $firstRunFile
)
$combinedBytes = [System.Collections.Generic.List[byte]]::new()
foreach ($hashFile in $hashInputFiles) {
    if (Test-Path $hashFile) {
        $combinedBytes.AddRange([System.IO.File]::ReadAllBytes($hashFile))
    }
}
$localContentHash = ([System.BitConverter]::ToString($sha256.ComputeHash($combinedBytes.ToArray())) -replace '-', '').ToLower()

$contentIsCurrent = Test-KeyVaultSecretValueCurrent `
    -VaultResourceId $keyVaultResourceId `
    -SecretName 'chatapp-content-hash' `
    -SecretValue $localContentHash

if (-not $DeployVm) {
    Write-Info 'VM deployment is disabled (deployVm: false) — skipping application bootstrap.'
    Remove-Item $firstRunFile -Force -ErrorAction SilentlyContinue
} elseif ($contentIsCurrent -and -not $ForceAppBootstrap) {
    Write-Exists 'App files unchanged since last deploy — skipping VM bootstrap.'
    Remove-Item $firstRunFile -Force -ErrorAction SilentlyContinue
} else {
    Write-Needed 'App files changed (or first deploy) — transferring through Azure VM Run Command...'
    Write-Info "[App package generation] completed in $($phaseWatch.Elapsed.ToString('mm\:ss'))"
    $phaseWatch.Restart()

    $vmReady = Ensure-VmRunning -ResourceGroupName $CoreResourceGroupName -VmName $vmName
    if (-not $vmReady) {
        Remove-Item $firstRunFile -Force -ErrorAction SilentlyContinue
        Write-Error '  Unable to guarantee the VM is running; cannot bootstrap the application.'
        exit 1
    }

    $bootstrapFiles = @(
        (Join-Path $appDir 'chat.py'),
        (Join-Path $appDir 'test.py'),
        (Join-Path $appDir 'requirements.txt'),
        $firstRunFile,
        $setupScript
    )
    $bootstrapSucceeded = Invoke-VmBootstrapPackage `
        -ResourceGroupName $CoreResourceGroupName `
        -VmName $vmName `
        -FilePaths $bootstrapFiles `
        -GuestTimeZone $VmGuestTimeZone
    Remove-Item $firstRunFile -Force -ErrorAction SilentlyContinue

    if (-not $bootstrapSucceeded) {
        Write-Error 'VM application bootstrap failed after multiple attempts.'
        exit 1
    }

    if (-not (Sync-KeyVaultSecretValue -VaultResourceId $keyVaultResourceId -SecretName 'chatapp-content-hash' -SecretValue $localContentHash)) {
        Write-Error 'Application bootstrap succeeded, but the content hash could not be recorded.'
        exit 1
    }
    Write-Exists '  Stored new app content hash.'
}

Write-Task 'Applying the deployment VM admin password...'
Write-Info "[VM application bootstrap] completed in $($phaseWatch.Elapsed.ToString('mm\:ss'))"
$phaseWatch.Restart()

# A rerun must never silently change a password the VM already has.
$skipVmPasswordApply = $preserveExistingVmPassword -or (-not $DeployVm)

if ($skipVmPasswordApply) {
    if ($DeployVm) {
        Write-Exists "  VM '$vmName' keeps the password assigned by a previous run — nothing was changed."
        Write-Info '  Use -RotateVmPassword to deliberately issue a new password.'
    } else {
        Write-Info '  VM deployment is disabled — skipping VM password handling.'
    }
} else {
    if ([string]::IsNullOrWhiteSpace($VmAdminPassword)) {
        Write-Error '  The deployment VM password is empty.'
        exit 1
    }

    $vmReady = Ensure-VmRunning `
        -ResourceGroupName $CoreResourceGroupName `
        -VmName $vmName

    if (-not $vmReady) {
        Write-Error '  Unable to guarantee the VM is running; cannot reset the password.'
        exit 1
    }

    Write-Info '  Applying the same password supplied to the VM deployment and stored in Key Vault.'
    $resetSucceeded = Update-VmUserPassword `
        -ResourceGroupName $CoreResourceGroupName `
        -VmName $vmName `
        -Username $VmAdminUsername `
        -Password $VmAdminPassword

    if ($resetSucceeded) {
        Write-Exists "  VM password applied for user '$VmAdminUsername'."
    } else {
        Write-Error "  Failed to reset VM password after multiple attempts."
        exit 1
    }
}

Write-Info "[VM password reset] completed in $($phaseWatch.Elapsed.ToString('mm\:ss'))"

if (-not $DeployVm) {
    Write-Info 'VM deployment is disabled — no VM credentials to report.'
} elseif ($preserveExistingVmPassword) {
    Write-Info ''
    Write-Needed 'VM LOGIN CREDENTIALS'
    Write-Info "  VM / host : $vmName ($vmPublicIpAddress)"
    Write-Info "  Username  : $VmAdminUsername"
    Write-Info '  Password  : unchanged from the previous run; this run neither read nor stored it.'
    Write-Needed 'Retrieve it from your password manager, or rerun with -RotateVmPassword to issue a new one.'
} elseif ($isCi) {
    Write-Info 'VM credentials are not printed or written to a workspace file in CI.'
    Write-Info 'Supply -VmAdminPassword from the CI secret store and retrieve it from that store when needed.'
} else {
    New-Item -ItemType Directory -Path $credentialDirectory -Force | Out-Null

    $credentialContent = @(
        "VM name: $vmName"
        "Public IP: $vmPublicIpAddress"
        "Username: $VmAdminUsername"
        "Password: $VmAdminPassword"
        "Generated: $([DateTimeOffset]::Now.ToString('o'))"
    )
    Set-Content -LiteralPath $credentialFile -Value $credentialContent -Encoding utf8NoBOM
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        & icacls.exe $credentialFile /inheritance:r /grant:r "${currentIdentity}:(F)" *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Info "  Warning: could not restrict file permissions on '$credentialFile'. Delete it immediately after saving the password."
        }
    }

    Write-Info ''
    Write-Needed 'VM LOGIN CREDENTIALS'
    Write-Info "  VM / host : $vmName ($vmPublicIpAddress)"
    Write-Info "  Username  : $VmAdminUsername"
    Write-Info "  Password  : $VmAdminPassword"
    Write-Info "  Saved to  : $credentialFile"
    Write-Needed 'Store this password in a password manager, then delete the credential file.'
    Write-Needed 'After confirming RDP access, change the VM password and update your password manager.'
}

Write-Exists 'Deployment complete.'
Complete-ScriptLogging -Status 'completed'
