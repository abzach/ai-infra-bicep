param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'uat')]
    [string] $EnvironmentSuffix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
. (Join-Path $scriptRoot 'config.ps1')

az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'An active Azure CLI session is required.'
}

$subscriptionId = (az account show --query id --output tsv 2>$null).Trim()
$configWithoutSuffix = Read-EnterpriseEnvironmentConfig -ScriptRoot $scriptRoot -EnvironmentSuffix $EnvironmentSuffix
$subscriptionId = Set-EnterpriseAzureSubscriptionContext -Config $configWithoutSuffix
$nameSuffix = Get-EnterpriseSubscriptionNameSuffix -SubscriptionId $subscriptionId
$config = Read-EnterpriseEnvironmentConfig -ScriptRoot $scriptRoot -EnvironmentSuffix $EnvironmentSuffix -NameSuffix $nameSuffix

$instanceViewErrorPath = Join-Path ([System.IO.Path]::GetTempPath()) "show-instance-view-$PID-$([guid]::NewGuid()).log"
try {
    $instanceViewJson = az vm get-instance-view `
        --subscription $subscriptionId `
        --resource-group $config.FoundationResourceGroupName `
        --name $config.vmName `
        --output json 2> $instanceViewErrorPath
    $instanceViewExitCode = $LASTEXITCODE
    $instanceViewError = ((Get-Content -LiteralPath $instanceViewErrorPath -Raw -ErrorAction SilentlyContinue) -join "`n").Trim()
} finally {
    Remove-Item -LiteralPath $instanceViewErrorPath -Force -ErrorAction SilentlyContinue
}
if ($instanceViewExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($instanceViewJson)) {
    $errorDetail = if ([string]::IsNullOrWhiteSpace($instanceViewError)) { 'Azure CLI returned no error details.' } else { $instanceViewError -replace '\s+', ' ' }
    throw "Unable to read the status of VM '$($config.vmName)': $errorDetail"
}

$instanceView = $instanceViewJson | ConvertFrom-Json
$vmStatuses = @($instanceView.instanceView.statuses)
$powerStatus = $vmStatuses | Where-Object { $_.code -like 'PowerState/*' } | Select-Object -First 1
$provisioningStatus = $vmStatuses | Where-Object { $_.code -like 'ProvisioningState/*' } | Select-Object -First 1
$agentStatus = @($instanceView.instanceView.vmAgent.statuses) | Select-Object -First 1
if (-not $powerStatus -or $powerStatus.code -ne 'PowerState/running' -or -not $agentStatus -or $agentStatus.displayStatus -ne 'Ready') {
    $statusDetails = @(
        if ($provisioningStatus) { "Provisioning: $($provisioningStatus.displayStatus) - $($provisioningStatus.message)" }
        if ($powerStatus) { "Power: $($powerStatus.displayStatus)" } else { 'Power: unavailable' }
        if ($agentStatus) { "VM agent: $($agentStatus.displayStatus) - $($agentStatus.message)" } else { 'VM agent: unavailable' }
    )
    throw "VM '$($config.vmName)' is not ready for password retrieval. $($statusDetails -join '; ')"
}

$identityClientId = (az identity show `
    --subscription $subscriptionId `
    --resource-group $config.FoundationResourceGroupName `
    --name $config.sharedManagedIdentityName `
    --query clientId `
    --output tsv 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($identityClientId)) {
    throw "Unable to resolve the managed identity for VM '$($config.vmName)'."
}

$vaultUri = "https://$($config.keyVaultName).vault.azure.net"
$remoteScript = @"
try {
    `$token = Invoke-RestMethod -Headers @{ Metadata = 'true' } -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net&client_id=$identityClientId' -Method Get -ErrorAction Stop
    `$secret = Invoke-RestMethod -Headers @{ Authorization = "Bearer `$(`$token.access_token)" } -Uri '$vaultUri/secrets/vm-admin-password?api-version=7.4' -Method Get -ErrorAction Stop
    `$encodedPassword = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]`$secret.value))
    Write-Output "__VM_PASSWORD_B64__`$encodedPassword"
} catch {
    `$statusCode = if (`$_.Exception.Response) { [int]`$_.Exception.Response.StatusCode } else { '' }
    Write-Output "__VM_PASSWORD_ERROR__`$statusCode `$(`$_.Exception.Message)"
}
"@

$remoteScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "show-password-$PID-$([guid]::NewGuid()).ps1"
$runCommandErrorPath = Join-Path ([System.IO.Path]::GetTempPath()) "show-run-command-$PID-$([guid]::NewGuid()).log"
Set-Content -LiteralPath $remoteScriptPath -Value $remoteScript -Encoding utf8NoBOM
try {
    $runResultJson = az vm run-command invoke `
        --subscription $subscriptionId `
        --resource-group $config.FoundationResourceGroupName `
        --name $config.vmName `
        --command-id RunPowerShellScript `
        --scripts "@$remoteScriptPath" `
        --output json 2> $runCommandErrorPath
    $runCommandExitCode = $LASTEXITCODE
    $runCommandError = ((Get-Content -LiteralPath $runCommandErrorPath -Raw -ErrorAction SilentlyContinue) -join "`n").Trim()
} finally {
    Remove-Item -LiteralPath $remoteScriptPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $runCommandErrorPath -Force -ErrorAction SilentlyContinue
}
if ($runCommandExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($runResultJson)) {
    $errorDetail = if ([string]::IsNullOrWhiteSpace($runCommandError)) { 'Azure CLI returned no error details.' } else { $runCommandError -replace '\s+', ' ' }
    throw "Unable to run the password retrieval command on VM '$($config.vmName)': $errorDetail"
}

$runResult = $runResultJson | ConvertFrom-Json
$message = (@($runResult.value) | ForEach-Object { [string]$_.message }) -join "`n"
$errorMatch = [regex]::Match($message, '(?m)__VM_PASSWORD_ERROR__(?<error>[^\r\n]*)')
if ($errorMatch.Success) {
    throw "The VM could not read the Key Vault password: $($errorMatch.Groups['error'].Value.Trim())"
}

$match = [regex]::Match($message, '(?m)__VM_PASSWORD_B64__(?<password>[A-Za-z0-9+/=]+)')
if (-not $match.Success) {
    $statusSummary = (@($runResult.value) | ForEach-Object { "$($_.code): $($_.displayStatus)" }) -join '; '
    throw "The VM command completed without returning the Key Vault password. Run Command statuses: $statusSummary"
}

$password = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($match.Groups['password'].Value))
Write-Host 'VM admin password: ' -NoNewline
Write-Host $password -ForegroundColor Yellow
Remove-Variable password, runResultJson, runResult, message, match, errorMatch, remoteScript, remoteScriptPath -ErrorAction SilentlyContinue