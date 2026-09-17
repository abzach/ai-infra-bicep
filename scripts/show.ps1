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
$nameSuffix = ($subscriptionId -replace '-', '').Substring(0, 4).ToLower()
$config = Read-EnterpriseEnvironmentConfig -ScriptRoot $scriptRoot -EnvironmentSuffix $EnvironmentSuffix -NameSuffix $nameSuffix

$identityClientId = (az identity show `
    --resource-group $config.coreResourceGroupName `
    --name $config.vmManagedIdentityName `
    --query clientId `
    --output tsv 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($identityClientId)) {
    throw "Unable to resolve the managed identity for VM '$($config.vmName)'."
}

$vaultUri = "https://$($config.keyVaultName).vault.azure.net"
$remoteScript = @"
`$token = Invoke-RestMethod -Headers @{ Metadata = 'true' } -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net&client_id=$identityClientId' -Method Get
`$secret = Invoke-RestMethod -Headers @{ Authorization = "Bearer `$(`$token.access_token)" } -Uri '$vaultUri/secrets/vm-admin-password?api-version=7.4' -Method Get
Write-Output "__VM_PASSWORD__`$(`$secret.value)"
"@

$runResultJson = az vm run-command invoke `
    --resource-group $config.coreResourceGroupName `
    --name $config.vmName `
    --command-id RunPowerShellScript `
    --scripts $remoteScript `
    --output json 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($runResultJson)) {
    throw "Unable to retrieve the VM password. Confirm '$($config.vmName)' is running and its managed identity can access Key Vault."
}

$runResult = $runResultJson | ConvertFrom-Json
$message = (@($runResult.value) | ForEach-Object { [string]$_.message }) -join "`n"
$match = [regex]::Match($message, '(?m)__VM_PASSWORD__(?<password>[^\r\n]+)')
if (-not $match.Success) {
    throw 'The VM command completed without returning the Key Vault password.'
}

$password = $match.Groups['password'].Value
Write-Host 'VM admin password: ' -NoNewline
Write-Host $password -ForegroundColor Yellow
Remove-Variable password, runResultJson, runResult, message, match -ErrorAction SilentlyContinue