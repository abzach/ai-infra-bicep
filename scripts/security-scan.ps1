param(
    [string] $TemplatePath = (Join-Path $PSScriptRoot '..\bicep\templates\main.bicep')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TemplateResources {
    param([Parameter(Mandatory)] [object] $Template)

    $resources = [System.Collections.Generic.List[object]]::new()
    $walkTemplate = {
        param([object] $CurrentTemplate)

        $templateResources = $CurrentTemplate.PSObject.Properties['resources']
        if ($null -eq $templateResources) {
            return
        }

        foreach ($resource in $templateResources.Value) {
            $resources.Add($resource)
            $propertiesProperty = $resource.PSObject.Properties['properties']
            if ($null -ne $propertiesProperty) {
                $nestedTemplateProperty = $propertiesProperty.Value.PSObject.Properties['template']
                if ($null -ne $nestedTemplateProperty) {
                    & $walkTemplate $nestedTemplateProperty.Value
                }
            }
        }
    }

    & $walkTemplate $Template
    return $resources
}

function Get-ResourcesOfType {
    param(
        [Parameter(Mandatory)] [System.Collections.Generic.List[object]] $Resources,
        [Parameter(Mandatory)] [string] $Type
    )

    return @($Resources | Where-Object { $_.type -eq $Type })
}

function Test-Rule {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message,
        [AllowEmptyCollection()]
        [Parameter(Mandatory)] [System.Collections.Generic.List[string]] $Failures
    )

    if ($Condition) {
        Write-Host "PASS: $Message"
    } else {
        Write-Host "FAIL: $Message" -ForegroundColor Red
        $Failures.Add($Message)
    }
}

function Resolve-BooleanTemplateValue {
    param(
        [Parameter(Mandatory)] [object] $Value,
        [Parameter(Mandatory)] [object] $Template
    )

    if ($Value -is [bool]) {
        return $Value
    }

    $parameterMatch = [regex]::Match([string] $Value, "^\[parameters\('([^']+)'\)\]$")
    if (-not $parameterMatch.Success) {
        return $false
    }

    $parameter = $Template.parameters.PSObject.Properties[$parameterMatch.Groups[1].Value]
    return $null -ne $parameter -and $parameter.Value.defaultValue -eq $true
}

if (-not (Test-Path -Path $TemplatePath -PathType Leaf)) {
    throw "Bicep template not found: $TemplatePath"
}

$templateJson = az bicep build --file $TemplatePath --stdout 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($templateJson)) {
    throw "Unable to compile Bicep template '$TemplatePath' for security scanning."
}

$template = $templateJson | ConvertFrom-Json
$resources = Get-TemplateResources -Template $template
$failures = [System.Collections.Generic.List[string]]::new()

$storageAccounts = Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Storage/storageAccounts'
Test-Rule -Condition ($storageAccounts.Count -gt 0) -Message 'A Storage account is defined.' -Failures $failures
foreach ($storageAccount in $storageAccounts) {
    Test-Rule -Condition ($storageAccount.properties.supportsHttpsTrafficOnly -eq $true) -Message 'Storage enforces HTTPS-only traffic.' -Failures $failures
    Test-Rule -Condition ($storageAccount.properties.minimumTlsVersion -in @('TLS1_2', 'TLS1_3')) -Message 'Storage requires TLS 1.2 or later.' -Failures $failures
    Test-Rule -Condition ($storageAccount.properties.allowBlobPublicAccess -eq $false) -Message 'Storage blocks anonymous blob access.' -Failures $failures
    Test-Rule -Condition ($storageAccount.properties.allowSharedKeyAccess -eq $false) -Message 'Storage blocks shared-key authorization.' -Failures $failures
    Test-Rule -Condition ($storageAccount.properties.networkAcls.defaultAction -eq 'Deny') -Message 'Storage network ACL defaults to deny.' -Failures $failures
}

$vaults = Get-ResourcesOfType -Resources $resources -Type 'Microsoft.KeyVault/vaults'
Test-Rule -Condition ($vaults.Count -gt 0) -Message 'A Key Vault is defined.' -Failures $failures
foreach ($vault in $vaults) {
    Test-Rule -Condition ($vault.properties.enableRbacAuthorization -eq $true) -Message 'Key Vault uses Azure RBAC authorization.' -Failures $failures
    Test-Rule -Condition ($vault.properties.networkAcls.defaultAction -eq 'Deny') -Message 'Key Vault network ACL defaults to deny.' -Failures $failures
}

$openAiAccounts = Get-ResourcesOfType -Resources $resources -Type 'Microsoft.CognitiveServices/accounts'
Test-Rule -Condition ($openAiAccounts.Count -gt 0) -Message 'An Azure OpenAI account is defined.' -Failures $failures
foreach ($openAiAccount in $openAiAccounts) {
    Test-Rule -Condition ($openAiAccount.properties.publicNetworkAccess -eq 'Disabled') -Message 'Azure OpenAI public network access is disabled.' -Failures $failures
    Test-Rule -Condition (Resolve-BooleanTemplateValue -Value $openAiAccount.properties.disableLocalAuth -Template $template) -Message 'Azure OpenAI local authentication is disabled.' -Failures $failures
}

$workspaces = Get-ResourcesOfType -Resources $resources -Type 'Microsoft.MachineLearningServices/workspaces'
Test-Rule -Condition ($workspaces.Count -ge 2) -Message 'AI Hub and Project workspaces are defined.' -Failures $failures
foreach ($workspace in $workspaces) {
    Test-Rule -Condition ($workspace.properties.publicNetworkAccess -eq 'Disabled') -Message "AI workspace '$($workspace.name)' public network access is disabled." -Failures $failures
}

$diagnosticSettings = Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Insights/diagnosticSettings'
Test-Rule -Condition ($diagnosticSettings.Count -ge 2) -Message 'Azure OpenAI and AI Hub diagnostic settings are present.' -Failures $failures
foreach ($diagnosticSetting in $diagnosticSettings) {
    Test-Rule -Condition (-not [string]::IsNullOrWhiteSpace([string] $diagnosticSetting.properties.workspaceId)) -Message "Diagnostic setting '$($diagnosticSetting.name)' has a Log Analytics destination." -Failures $failures
}

$publicIps = Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Network/publicIPAddresses'
foreach ($publicIp in $publicIps) {
    Test-Rule -Condition ($publicIp.sku.name -eq 'Standard') -Message "Public IP '$($publicIp.name)' uses the Standard SKU." -Failures $failures
    Test-Rule -Condition ($publicIp.properties.publicIPAllocationMethod -eq 'Static') -Message "Public IP '$($publicIp.name)' uses static allocation." -Failures $failures
}

if ($failures.Count -gt 0) {
    throw "IaC security scan failed with $($failures.Count) violation(s): $($failures -join '; ')"
}

Write-Host 'IaC security scan passed.' -ForegroundColor Green