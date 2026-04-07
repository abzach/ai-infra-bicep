# deploy.ps1 — Main infrastructure deployment orchestrator.
#
# EXAMPLES
#   # Full dev deploy
#   .\deploy.ps1 -EnvironmentSuffix dev
#
#   # Preview changes without deploying
#   .\deploy.ps1 -EnvironmentSuffix dev -WhatIf
#
#   # Add your current public IP to KV and storage firewalls for direct access
#   .\deploy.ps1 -EnvironmentSuffix dev -Action myip
#
#   # Deploy with a specific VM password (also stores it in Key Vault)
#   .\deploy.ps1 -EnvironmentSuffix dev -VmAdminPassword 'MyP@ss123!'
#
# PREREQUISITES
#   - Azure CLI installed and `az login` completed (Owner or User Access Administrator on sub)
#   - PowerShell 7+ recommended
#   - config.ps1 and common.ps1 must be present in the same directory

param(
    [Parameter(Mandatory)] [ValidateSet('dev','uat')] [string] $EnvironmentSuffix,
    [ValidateSet('deploy','myip')] [string] $Action = 'deploy',
    [string] $VmAdminPassword,
    [switch] $ForceAppBootstrap,
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

    throw 'Unable to resolve the script root for deploy.ps1.'
}

$scriptRoot = Get-CurrentScriptRoot

. (Join-Path $scriptRoot 'config.ps1')
. (Join-Path $scriptRoot 'common.ps1')

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

function Wait-KeyVaultDnsResolution {
    param(
        [Parameter(Mandatory)] [string] $VaultName,
        [int] $MaxAttempts = 8,
        [int] $DelaySeconds = 10
    )

    $vaultHost = "$VaultName.vault.azure.net"

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $addresses = [System.Net.Dns]::GetHostAddresses($vaultHost)
            if ($addresses.Count -gt 0) {
                return $true
            }
        } catch {
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Info "  Waiting for DNS resolution of '$vaultHost' (attempt $attempt/$MaxAttempts)..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return $false
}

function Test-KeyVaultAccessRetryableFailure {
    param(
        [AllowNull()] [string] $OutputText
    )

    if ([string]::IsNullOrWhiteSpace($OutputText)) {
        return $false
    }

    return $OutputText -match 'ForbiddenByConnection|ForbiddenByFirewall|ForbiddenByRbac|Public network access is disabled|Client address|network access is denied|does not have secrets (get|set|list) permission|Status: 403|status code 403|invalid status ''Forbidden''' 
}

function Sync-KeyVaultSecretValue {
    param(
        [Parameter(Mandatory)] [string] $VaultName,
        [Parameter(Mandatory)] [string] $SecretName,
        [Parameter(Mandatory)] [string] $SecretValue,
        [int] $MaxAttempts = 12,
        [int] $DelaySeconds = 15
    )

    if ([string]::IsNullOrWhiteSpace($SecretValue)) {
        return $true
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $existingSecretValueResult = Invoke-AzCliWithRetry `
            -Operation "read secret '$SecretName' from Key Vault '$VaultName'" `
            -MaxAttempts 1 `
            -DelaySeconds $DelaySeconds `
            -Command {
                az keyvault secret show `
                    --vault-name $VaultName `
                    --name $SecretName `
                    --query value `
                    --output tsv
            }

        $existingValue = if ($existingSecretValueResult.Success -and -not [string]::IsNullOrWhiteSpace($existingSecretValueResult.Output)) {
            $existingSecretValueResult.Output.Trim()
        } else {
            ''
        }

        $secretNeedsUpdate = (-not $existingSecretValueResult.Success) -or ($existingValue -ne $SecretValue.Trim())

        if ($secretNeedsUpdate) {
            $updatedSecretResult = Invoke-AzCliWithRetry `
                -Operation "write secret '$SecretName' to Key Vault '$VaultName'" `
                -MaxAttempts 1 `
                -DelaySeconds $DelaySeconds `
                -Command {
                    az keyvault secret set `
                        --vault-name $VaultName `
                        --name $SecretName `
                        "--value=$SecretValue" `
                        --query id `
                        --output tsv
                }

            if ($updatedSecretResult.Success -and -not [string]::IsNullOrWhiteSpace($updatedSecretResult.Output)) {
                $updatedSecretId = $updatedSecretResult.Output.Trim()
                $updatedVersion = ($updatedSecretId -split '/')[-1]
                Write-Exists "  Updated secret '$SecretName' (version: $updatedVersion)."
                return $true
            }

            $canRetry = Test-KeyVaultAccessRetryableFailure -OutputText $updatedSecretResult.Output
            if ($canRetry -and $attempt -lt $MaxAttempts) {
                Write-Info "  Waiting for Key Vault data-plane access to sync '$SecretName' (attempt $attempt/$MaxAttempts)..."
                Start-Sleep -Seconds $DelaySeconds
                continue
            }

            Write-Info "  Warning: failed to update secret '$SecretName'."
            if (-not [string]::IsNullOrWhiteSpace($updatedSecretResult.Output)) {
                Write-Info "  Key Vault error details: $($updatedSecretResult.Output)"
            }

            return $false
        }

        $existingSecretIdResult = Invoke-AzCliWithRetry `
            -Operation "read secret metadata '$SecretName' from Key Vault '$VaultName'" `
            -MaxAttempts 1 `
            -DelaySeconds $DelaySeconds `
            -Command {
                az keyvault secret show `
                    --vault-name $VaultName `
                    --name $SecretName `
                    --query id `
                    --output tsv
            }

        if ($existingSecretIdResult.Success -and -not [string]::IsNullOrWhiteSpace($existingSecretIdResult.Output)) {
            $existingSecretId = $existingSecretIdResult.Output.Trim()
            $existingVersion = ($existingSecretId -split '/')[-1]
            Write-Exists "  Secret '$SecretName' already current (version: $existingVersion)."
            return $true
        }

        $canRetry = Test-KeyVaultAccessRetryableFailure -OutputText $existingSecretIdResult.Output
        if ($canRetry -and $attempt -lt $MaxAttempts) {
            Write-Info "  Waiting for Key Vault data-plane access to confirm '$SecretName' (attempt $attempt/$MaxAttempts)..."
            Start-Sleep -Seconds $DelaySeconds
            continue
        }

        Write-Exists "  Secret '$SecretName' already current."
        return $true
    }

    return $false
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
$CoreResourceGroupName           = $config.coreResourceGroupName
$NetworkResourceGroupName        = $config.networkResourceGroupName
$SkuName                         = $config.skuName
$ModelDeploymentName             = $config.modelDeploymentName
$ModelName                       = $config.modelName
$ModelVersion                    = $config.modelVersion
$ModelSkuName                    = $config.modelSkuName
$CapacityK                       = [int]$config.capacityK
$SecondaryModelDeploymentName    = $config.secondaryModelDeploymentName
$SecondaryModelName              = $config.secondaryModelName
$SecondaryModelVersion           = $config.secondaryModelVersion
$SecondaryModelSkuName           = $config.secondaryModelSkuName
$SecondaryCapacityK              = [int]$config.secondaryCapacityK
$AdminObjectIds                  = ($config.adminObjectIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
$VmAdminUsername                 = $config.vmAdminUsername
$MlApiVersion                    = $config.mlApiVersion
$VmUseSpot                       = Convert-ToBoolean -Value $config.vmUseSpot -Default $true
$VmSpotMaxPrice                  = [int]$config.vmSpotMaxPrice
$VmAutoShutdownEnabled           = Convert-ToBoolean -Value $config.vmAutoShutdownEnabled -Default $true
$VmAutoShutdownTime              = $config.vmAutoShutdownTime
$VmAutoShutdownTimeZone          = $config.vmAutoShutdownTimeZone
$PrivateAiWorkspacesOnly         = Convert-ToBoolean -Value $config.privateAiWorkspacesOnly -Default $true
$EnableAuditDiagnostics          = Convert-ToBoolean -Value $config.enableAuditDiagnostics -Default $true
$LogAnalyticsRetentionDays       = [int]$config.logAnalyticsRetentionDays
$LogAnalyticsDailyQuotaGb        = $config.logAnalyticsDailyQuotaGb
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
$managedIdentityName = $config.managedIdentityName

$tenantIdRaw = az account show --query tenantId --output tsv 2>$null
$tenantId = if (-not [string]::IsNullOrWhiteSpace($tenantIdRaw)) { $tenantIdRaw.Trim() } else { '' }
Write-Info "  TenantId (for first-run device login): $tenantId"

$adminUpn = $AdminObjectIds[0]

if ($Action -eq 'myip') {
    Write-Task 'Detecting public IP address...'
    $localPublicIp = Get-PublicIpAddress
    if ([string]::IsNullOrWhiteSpace($localPublicIp)) {
        Write-Error 'Could not determine the public IP of this machine.'
        exit 1
    }
    $localPublicIpCidr = "$localPublicIp/32"
    Write-Info "  Public IP detected: $localPublicIp"

    Write-Task "  Adding firewall rule $localPublicIpCidr to Key Vault '$keyVaultName'..."
    az keyvault network-rule add `
        --name $keyVaultName `
        --resource-group $CoreResourceGroupName `
        --ip-address $localPublicIpCidr `
        --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Exists "  Firewall rule added to Key Vault '$keyVaultName'."
    } else {
        Write-Needed "  Warning: could not add firewall rule to Key Vault '$keyVaultName' (vault may not exist yet)."
    }

    Write-Task "  Adding firewall rule $localPublicIp to Storage Account '$storageAccountName'..."
    az storage account network-rule add `
        --resource-group $CoreResourceGroupName `
        --account-name $storageAccountName `
        --ip-address $localPublicIp `
        --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Exists "  Firewall rule added to Storage Account '$storageAccountName'."
    } else {
        Write-Needed "  Warning: could not add firewall rule to Storage Account '$storageAccountName' (account may not exist yet)."
    }

    Write-Exists 'Done.'
    exit 0
}

Write-Task 'Verifying deploying identity has role-assignment write permission...'
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
    } else {
        $AdminObjectIds[0]
    }
}

if ([string]::IsNullOrWhiteSpace($deployingObjectId)) {
    Write-Error 'Could not determine the object ID of the current identity. Ensure you are logged in with az login.'
    exit 1
}
Write-Info "  Deploying identity object ID: $deployingObjectId  (type: $accountType)"

$subScope = "/subscriptions/$subscriptionId"
$privilegedRoles = az role assignment list `
    --assignee $deployingObjectId `
    --scope $subScope `
    --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='User Access Administrator'].roleDefinitionName" `
    --output tsv 2>$null
$hasRoleAssignWrite = ($LASTEXITCODE -eq 0) -and (-not [string]::IsNullOrWhiteSpace($privilegedRoles))

if (-not $hasRoleAssignWrite) {
    Write-Error @"
The deploying identity ($deployingObjectId, type: $accountType) does not have 'Owner' or
'User Access Administrator' role at subscription scope '$subScope'.

This role is required because the Bicep template creates Azure RBAC role assignments
for the managed identity (Storage Blob Data Contributor, Key Vault Secrets User,
Cognitive Services OpenAI User).

One-time fix — run the following as a subscription Owner or Global Admin:
  az role assignment create \
    --role "User Access Administrator" \
    --assignee "$deployingObjectId" \
    --scope "$subScope"

For the Azure DevOps service connection (object ID shown above), you can also assign
the 'Owner' role via the Azure portal:
  Subscription -> Access control (IAM) -> Add role assignment -> Owner -> select the SP.
"@
    exit 1
}
Write-Exists "  Identity has '$($privilegedRoles.Trim())' at subscription scope — role-assignment write confirmed."

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
}

Write-Task 'Detecting public IP address for Key Vault firewall whitelist...'
$localPublicIp = Get-PublicIpAddress
if ([string]::IsNullOrWhiteSpace($localPublicIp)) {
    Write-Error 'Could not determine the public IP of this machine. Cannot proceed with Key Vault operations.'
    exit 1
}
$localPublicIpCidr = "$localPublicIp/32"
$keyVaultIpAllowList = @($localPublicIpCidr)
$storageIpAllowList = @($localPublicIp)
Write-Info "  Public IP detected: $localPublicIp"
Write-Info "  Trying to add network firewall rule '$localPublicIpCidr' to Key Vault '$keyVaultName'..."
az keyvault network-rule add `
    --name $keyVaultName `
    --resource-group $CoreResourceGroupName `
    --ip-address $localPublicIpCidr `
    --output none 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Exists "  Firewall rule '$localPublicIpCidr' added to Key Vault '$keyVaultName'."
    Write-Info '  Waiting for Key Vault firewall rule to propagate...'
    Start-Sleep -Seconds 15
} else {
    Write-Needed "  Could not add the rule because Key Vault '$keyVaultName' does not exist."
    Write-Info "  Key Vault '$keyVaultName' will be deployed using Bicep templates shortly, we will try adding the rules again after."
}

Write-Info "  Trying to add network firewall rule '$localPublicIpCidr' to Storage Account '$storageAccountName'..."
az storage account network-rule add `
    --resource-group $CoreResourceGroupName `
    --account-name $storageAccountName `
    --ip-address $localPublicIp `
    --output none 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Exists "  Firewall rule '$localPublicIp' added to Storage Account '$storageAccountName'."
    Write-Info '  Waiting for Storage Account firewall rule to propagate...'
    Start-Sleep -Seconds 15
} else {
    Write-Needed "  Could not add the rule because Storage Account '$storageAccountName' does not exist."
    Write-Info "  Storage Account '$storageAccountName' will be deployed using Bicep templates shortly, we will try adding the rules again after."
}

if ([string]::IsNullOrWhiteSpace($VmAdminPassword)) {
    $existingVmAdminPassword = az keyvault secret show `
        --vault-name $keyVaultName `
        --name 'vm-admin-password' `
        --query value `
        --output tsv 2>$null

    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($existingVmAdminPassword)) {
        $VmAdminPassword = $existingVmAdminPassword.Trim()
        $isNewVmPassword = $false
        Write-Exists 'Reusing existing VM admin password from Key Vault.'
    } else {
        $existingVmId = az vm show --resource-group $CoreResourceGroupName --name $vmName --query id --output tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($existingVmId)) {
            Write-Needed "  Warning: VM '$vmName' exists but Key Vault secret is not accessible. Generating a new VM password for this deployment."
        }

        $VmAdminPassword = New-SecurePassword
        $isNewVmPassword = $true
        Write-Exists 'Generated a new VM admin password for first-time deployment.'
    }
} else {
    $isNewVmPassword = $true
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
        skuName = @{ value = $SkuName }
        adminObjectIds = @{ value = @($AdminObjectIds) }
        modelDeploymentName = @{ value = $ModelDeploymentName }
        modelName = @{ value = $ModelName }
        modelVersion = @{ value = $ModelVersion }
        modelSkuName = @{ value = $ModelSkuName }
        capacityK = @{ value = $CapacityK }
        secondaryModelDeploymentName = @{ value = $SecondaryModelDeploymentName }
        secondaryModelName = @{ value = $SecondaryModelName }
        secondaryModelVersion = @{ value = $SecondaryModelVersion }
        secondaryModelSkuName = @{ value = $SecondaryModelSkuName }
        secondaryCapacityK = @{ value = $SecondaryCapacityK }
        vmAdminUsername = @{ value = $VmAdminUsername }
        vmAdminPassword = @{ value = $VmAdminPassword }
        tags = @{ value = $deploymentTags }
        vmUseSpot = @{ value = $VmUseSpot }
        vmSpotMaxPrice = @{ value = $VmSpotMaxPrice }
        vmAutoShutdownEnabled = @{ value = $VmAutoShutdownEnabled }
        vmAutoShutdownTime = @{ value = $VmAutoShutdownTime }
        vmAutoShutdownTimeZone = @{ value = $VmAutoShutdownTimeZone }
        privateAiWorkspacesOnly = @{ value = $PrivateAiWorkspacesOnly }
        logAnalyticsRetentionDays = @{ value = $LogAnalyticsRetentionDays }
        keyVaultIpAllowList = @{ value = $keyVaultIpAllowList }
        storageIpAllowList = @{ value = $storageIpAllowList }
        rdpAllowedIpCidrs = @{ value = $keyVaultIpAllowList }
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

$miPrincipalId = az identity show `
    --resource-group $CoreResourceGroupName `
    --name $managedIdentityName `
    --query principalId `
    --output tsv 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($miPrincipalId)) {
    Write-Task 'Removing stale managed identity role assignments before deployment...'
    $miRoleGuids = @(
        'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
        '4633458b-17de-408a-b874-0445c86b69e6'
        '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    )
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
                        Write-Exists "  Removed role '$roleGuid'."
                    }
                }
            }
        }
    }
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
    Write-Exists 'What-if completed. Skipping secret sync and app packaging.'
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
$managedIdentityClientId = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'managedIdentityClientId').Trim()
$logAnalyticsWorkspaceId = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'logAnalyticsWorkspaceId').Trim()
$logAnalyticsWorkspaceName = (Get-DeploymentOutputValue -Outputs $deploymentOutputs -Name 'logAnalyticsWorkspaceName').Trim()
if ([string]::IsNullOrWhiteSpace($managedIdentityClientId)) {
    $managedIdentityClientIdRaw = az identity show --resource-group $CoreResourceGroupName --name $managedIdentityName --query clientId --output tsv 2>$null
    $managedIdentityClientId = if (-not [string]::IsNullOrWhiteSpace($managedIdentityClientIdRaw)) { $managedIdentityClientIdRaw.Trim() } else { '' }
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
    if (-not [string]::IsNullOrWhiteSpace($logAnalyticsWorkspaceName)) {
        Set-LogAnalyticsDailyQuota `
            -ResourceGroupName $CoreResourceGroupName `
            -WorkspaceName $logAnalyticsWorkspaceName `
            -DailyQuotaGb $LogAnalyticsDailyQuotaGb
    }

    if ($EnableAuditDiagnostics -and -not [string]::IsNullOrWhiteSpace($logAnalyticsWorkspaceId)) {
        Set-AuditDiagnosticsForImportantResources `
            -CoreResourceGroupName $CoreResourceGroupName `
            -NetworkResourceGroupName $NetworkResourceGroupName `
            -WorkspaceId $logAnalyticsWorkspaceId
    }
} catch {
    Write-Info "  Warning: post-deploy diagnostics configuration encountered an error (non-fatal): $_"
}

Write-Task 'Syncing Key Vault secrets...'
if (-not (Wait-KeyVaultDnsResolution -VaultName $keyVaultName)) {
    Write-Error "Unable to resolve Key Vault DNS name '$keyVaultName.vault.azure.net' after waiting. Check DNS/firewall/private endpoint connectivity and retry deployment."
    exit 1
}
$secretSyncFailures = @()
if (-not (Sync-KeyVaultSecretValue -VaultName $keyVaultName -SecretName 'openai-endpoint' -SecretValue $openAiEndpoint)) {
    $secretSyncFailures += 'openai-endpoint'
}
if (-not (Sync-KeyVaultSecretValue -VaultName $keyVaultName -SecretName 'openai-deployment' -SecretValue $openAiDeployment)) {
    $secretSyncFailures += 'openai-deployment'
}
if (-not (Sync-KeyVaultSecretValue -VaultName $keyVaultName -SecretName 'openai-secondary-deployment' -SecretValue $openAiSecondaryDeployment)) {
    $secretSyncFailures += 'openai-secondary-deployment'
}
if (-not [string]::IsNullOrWhiteSpace($VmAdminPassword)) {
    if (-not (Sync-KeyVaultSecretValue -VaultName $keyVaultName -SecretName 'vm-admin-password' -SecretValue $VmAdminPassword)) {
        $secretSyncFailures += 'vm-admin-password'
    }
} else {
    Write-Info "  Skipping vm-admin-password sync because the password is not available."
}
if (-not (Sync-KeyVaultSecretValue -VaultName $keyVaultName -SecretName 'keyvault-url' -SecretValue $keyVaultUrl)) {
    $secretSyncFailures += 'keyvault-url'
}
if (-not [string]::IsNullOrWhiteSpace($managedIdentityClientId)) {
    if (-not (Sync-KeyVaultSecretValue -VaultName $keyVaultName -SecretName 'managed-identity-client-id' -SecretValue $managedIdentityClientId)) {
        $secretSyncFailures += 'managed-identity-client-id'
    }
}
$openAiApiVersion = if (-not [string]::IsNullOrWhiteSpace($config.openaiApiVersion)) { $config.openaiApiVersion } else { '2025-01-01-preview' }
if (-not (Sync-KeyVaultSecretValue -VaultName $keyVaultName -SecretName 'openai-api-version' -SecretValue $openAiApiVersion)) {
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
$null = Sync-KeyVaultSecretValue -VaultName $keyVaultName -SecretName 'config-version' -SecretValue $configVersionHash
Write-Exists "  Config version hash stored: $configVersionHash"

Write-Task 'Generating first-run.ps1 for VM...'
Write-Info "[Secrets sync] completed in $($phaseWatch.Elapsed.ToString('mm\:ss'))"
$phaseWatch.Restart()
$firstRunFile = Join-Path $tempDir "first-run-$EnvironmentSuffix.$PID.ps1"

# Values are substituted directly into the script at deploy time so the VM
# does not need any parameters — it is self-contained.
$firstRunContent = @"
`$ErrorActionPreference = 'Stop'

`$KeyVaultName  = '$keyVaultName'
`$KeyVaultUrl   = '$keyVaultUrl'
`$MiClientId    = '$managedIdentityClientId'
`$AdminObjectId = '$($AdminObjectIds[0])'
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

$storedContentHash = (az keyvault secret show `
    --vault-name $keyVaultName `
    --name 'chatapp-content-hash' `
    --query value `
    --output tsv 2>$null)
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($storedContentHash)) {
    $storedContentHash = $storedContentHash.Trim().ToLower()
} else {
    $storedContentHash = ''
}

if ($localContentHash -eq $storedContentHash -and -not $ForceAppBootstrap) {
    Write-Exists 'App files unchanged since last deploy — skipping upload and Custom Script Extension.'
    Remove-Item $firstRunFile -Force -ErrorAction SilentlyContinue
} else {
    Write-Needed 'App files changed (or first deploy) — uploading and applying Custom Script Extension...'

    if (-not [string]::IsNullOrWhiteSpace($localPublicIp)) {
        Write-Info "  Ensuring deployer IP $localPublicIp is still allowed on Storage Account '$storageAccountName'..."

        az storage account network-rule add `
            --resource-group $CoreResourceGroupName `
            --account-name $storageAccountName `
            --ip-address $localPublicIp `
            --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Exists "  Firewall rule '$localPublicIp' added to Storage Account '$storageAccountName'."
        }
        Write-Info "  Waiting for Storage firewall rule to propagate..."
        Start-Sleep -Seconds 30
    }

    Write-Info "Syncing storage account key secret in Key Vault..."
    $storageAccountKeyResult = Invoke-AzCliWithRetry `
        -Operation "retrieve storage account key for '$storageAccountName'" `
        -DelaySeconds 12 `
        -Command {
            az storage account keys list `
                --resource-group $CoreResourceGroupName `
                --account-name $storageAccountName `
                --query '[0].value' `
                --output tsv
        }

    $storageAccountKey = if ($storageAccountKeyResult.Success -and -not [string]::IsNullOrWhiteSpace($storageAccountKeyResult.Output)) {
        $storageAccountKeyResult.Output.Trim()
    } else {
        ''
    }

    if ([string]::IsNullOrWhiteSpace($storageAccountKey)) {
        Write-Error "Failed to retrieve storage account key (exit code: $($storageAccountKeyResult.ExitCode))."
        if (-not [string]::IsNullOrWhiteSpace($storageAccountKeyResult.Output)) {
            Write-Error "Azure CLI details: $($storageAccountKeyResult.Output)"
        }
        exit 1
    }

    $null = Sync-KeyVaultSecretValue -VaultName $keyVaultName -SecretName 'storage-account-key' -SecretValue $storageAccountKey

    $storageAccountKey2Result = Invoke-AzCliWithRetry `
        -Operation "retrieve storage account key2 for '$storageAccountName'" `
        -DelaySeconds 12 `
        -Command {
            az storage account keys list `
                --resource-group $CoreResourceGroupName `
                --account-name $storageAccountName `
                --query '[1].value' `
                --output tsv
        }

    if ($storageAccountKey2Result.Success -and -not [string]::IsNullOrWhiteSpace($storageAccountKey2Result.Output)) {
        $null = Sync-KeyVaultSecretValue -VaultName $keyVaultName -SecretName 'storage-account-key2' -SecretValue $storageAccountKey2Result.Output.Trim()
    }

    $containerExists = az storage container exists `
        --account-name $storageAccountName `
        --auth-mode login `
        --name $containerName `
        --query exists `
        --output tsv 2>$null

    if ($containerExists -ne 'true') {
        Write-Info "  Creating container '$containerName'..."
        az storage container create `
            --account-name $storageAccountName `
            --auth-mode login `
            --name $containerName `
            --output none 2>$null
    }

    foreach ($file in @('chat.py', 'test.py', 'requirements.txt')) {
        $filePath = Join-Path $appDir $file
        if (Test-Path $filePath) {
            az storage blob upload `
                --account-name $storageAccountName `
                --auth-mode login `
                --container-name $containerName `
                --file $filePath `
                --name $file `
                --overwrite `
                --output none
            
            if ($LASTEXITCODE -ne 0) {
                Remove-Item $firstRunFile -Force -ErrorAction SilentlyContinue
                Write-Error "Failed to upload $file to blob storage."
                exit 1
            }

            Write-Exists "  Uploaded $file"
        }
    }

    az storage blob upload `
        --account-name $storageAccountName `
        --auth-mode login `
        --container-name $containerName `
        --file $firstRunFile `
        --name 'first-run.ps1' `
        --overwrite `
        --output none

    if ($LASTEXITCODE -ne 0) {
        Remove-Item $firstRunFile -Force -ErrorAction SilentlyContinue
        Write-Error 'Failed to upload first-run.ps1 to blob storage.'
        exit 1
    }

    Write-Exists '  Uploaded first-run.ps1'

    az storage blob upload `
        --account-name $storageAccountName `
        --auth-mode login `
        --container-name $containerName `
        --file $setupScript `
        --name 'setup.ps1' `
        --overwrite `
        --output none

    if ($LASTEXITCODE -ne 0) {
        Remove-Item $firstRunFile -Force -ErrorAction SilentlyContinue
        Write-Error 'Failed to upload setup.ps1 to blob storage.'
        exit 1
    }

    Write-Exists '  Uploaded setup.ps1'
    Remove-Item $firstRunFile -Force -ErrorAction SilentlyContinue

    Write-Exists "  Retaining firewall rule '$localPublicIpCidr' on Key Vault '$keyVaultName' for ongoing access."

    Write-Task 'Applying Custom Script Extension to VM...'
    Write-Info "[App packaging + upload] completed in $($phaseWatch.Elapsed.ToString('mm\:ss'))"
    $phaseWatch.Restart()

    $vmReady = Ensure-VmRunning -ResourceGroupName $CoreResourceGroupName -VmName $vmName
    if (-not $vmReady) {
        Write-Error '  Unable to guarantee the VM is running; cannot apply Custom Script Extension.'
        exit 1
    }

    $managedIdentityClientId = az identity show `
        --resource-group $CoreResourceGroupName `
        --name $managedIdentityName `
        --query clientId -o tsv

    $blobBase = "https://${storageAccountName}.blob.core.windows.net/${containerName}"

    $settingsFile          = Join-Path $tempDir "cse-settings-$PID.json"
    $protectedSettingsFile = Join-Path $tempDir "cse-protected-settings-$PID.json"

    $settingsObject = @{
        fileUris = @(
            "${blobBase}/setup.ps1",
            "${blobBase}/chat.py",
            "${blobBase}/test.py",
            "${blobBase}/requirements.txt",
            "${blobBase}/first-run.ps1"
        )
        commandToExecute = "powershell -ExecutionPolicy Bypass -File setup.ps1"
    }

    $protectedSettingsObject = @{
        managedIdentity = @{
            clientId = $managedIdentityClientId
        }
    }

    $settingsObject          | ConvertTo-Json -Compress | Out-File $settingsFile          -Encoding UTF8
    $protectedSettingsObject | ConvertTo-Json -Compress | Out-File $protectedSettingsFile -Encoding UTF8

    $extensionApplied = $false
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        az vm extension set `
            --resource-group $CoreResourceGroupName `
            --vm-name $vmName `
            --name CustomScriptExtension `
            --publisher Microsoft.Compute `
            --version 1.10 `
            --force-update `
            --settings "@$settingsFile" `
            --protected-settings "@$protectedSettingsFile" `
            --output table

        if ($LASTEXITCODE -eq 0) {
            $extensionApplied = $true
            break
        }

        if ($attempt -lt 4) {
            Write-Info "  Warning: Custom Script Extension attempt $attempt failed. Waiting 45 seconds before retrying..."
            Start-Sleep -Seconds 45
        }
    }

    Remove-Item $settingsFile, $protectedSettingsFile -Force -ErrorAction SilentlyContinue

    if (-not $extensionApplied) {
        Write-Error 'Custom Script Extension failed after multiple attempts.'
        exit 1
    }

    $null = Sync-KeyVaultSecretValue -VaultName $keyVaultName -SecretName 'chatapp-content-hash' -SecretValue $localContentHash
    Write-Exists '  Stored new app content hash.'
}

Write-Task 'Resetting VM admin password from Key Vault...'
Write-Info "[Custom Script Extension] completed in $($phaseWatch.Elapsed.ToString('mm\:ss'))"
$phaseWatch.Restart()
$kvSecretJson = az keyvault secret show `
    --vault-name $keyVaultName `
    --name 'vm-admin-password' `
    --query '{value:value,id:id}' `
    --output json 2>$null

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($kvSecretJson)) {
    Write-Error "  Unable to read 'vm-admin-password' from Key Vault — cannot guarantee VM credentials."
    exit 1
}

try {
    $kvSecret = $kvSecretJson | ConvertFrom-Json
} catch {
    Write-Error "  Unable to parse Key Vault secret payload for 'vm-admin-password'."
    exit 1
}

$kvVmPassword = if ($kvSecret.value) { $kvSecret.value.Trim() } else { '' }
$kvVmPasswordVersion = if ($kvSecret.id) { ($kvSecret.id -split '/')[-1] } else { '<unknown>' }

if ([string]::IsNullOrWhiteSpace($kvVmPassword)) {
    Write-Error "  Key Vault secret 'vm-admin-password' is empty."
    exit 1
}

$vmReady = Ensure-VmRunning `
    -ResourceGroupName $CoreResourceGroupName `
    -VmName $vmName

if (-not $vmReady) {
    Write-Error '  Unable to guarantee the VM is running; cannot reset the password.'
    exit 1
}

Write-Info "  Applying vm-admin-password from Key Vault version $kvVmPasswordVersion."
$resetSucceeded = Update-VmUserPassword `
    -ResourceGroupName $CoreResourceGroupName `
    -VmName $vmName `
    -Username $VmAdminUsername `
    -Password $kvVmPassword

if ($resetSucceeded) {
    Write-Exists "  VM password reset to Key Vault secret version $kvVmPasswordVersion for user '$VmAdminUsername'."
} else {
    Write-Error "  Failed to reset VM password after multiple attempts."
    exit 1
}

Write-Info "[VM password reset] completed in $($phaseWatch.Elapsed.ToString('mm\:ss'))"
Write-Exists 'Deployment complete.'
