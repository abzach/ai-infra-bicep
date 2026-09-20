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
Set-Content -LiteralPath $remoteScriptPath -Value $remoteScript -Encoding utf8NoBOM
try {
    $runResultJson = az vm run-command invoke `
        --subscription $subscriptionId `
        --resource-group $config.WorkloadResourceGroupName `
        --name $config.vmName `
        --command-id RunPowerShellScript `
        --scripts "@$remoteScriptPath" `
        --output json 2>$null
} finally {
    Remove-Item -LiteralPath $remoteScriptPath -Force -ErrorAction SilentlyContinue
}
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($runResultJson)) {
    throw "Unable to retrieve the VM password. Confirm '$($config.vmName)' is running and its managed identity can access Key Vault."
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