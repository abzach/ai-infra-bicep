# config.ps1 — Configuration helpers shared by deploy.ps1, test.ps1, and cleanup.ps1.

function Convert-ConfigScalar {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $trimmed = $Value.Trim()
    $trimmed = $trimmed -replace '\s+#.*$', ''
    if ($trimmed.Length -ge 2) {
        $first = $trimmed[0]
        $last = $trimmed[$trimmed.Length - 1]
        if (($first -eq "'" -and $last -eq "'") -or ($first -eq '"' -and $last -eq '"')) {
            $trimmed = $trimmed.Substring(1, $trimmed.Length - 2)
        }
    }

    return $trimmed
}

# ---------------------------------------------------------------------------
# Get-EnterpriseResourceNames
#   Computes all Azure resource names from the three naming inputs so that
#   every script uses the same deterministic naming scheme.
#
#   Parameters
#     BaseName          Short workload prefix (e.g. "mstech", max 5-8 chars)
#     EnvironmentSuffix Environment token: "dev" or "uat"
#     NameSuffix        Optional 4-char subscription-derived suffix for global uniqueness
#
#   Returns a pscustomobject with properties:
#     coreResourceGroupName, networkResourceGroupName, storageAccountName,
#     keyVaultName, openAiAccountName, hubName, projectName,
#     managedIdentityName, vnetName, vmName, lawWorkspaceName
# ---------------------------------------------------------------------------
function Get-EnterpriseResourceNames {
    param(
        [Parameter(Mandatory)] [string] $BaseName,
        [Parameter(Mandatory)] [string] $EnvironmentSuffix,
        [string] $NameSuffix = ''
    )

    $n   = $BaseName.ToLower()
    $env = $EnvironmentSuffix.ToLower()
    $sfx = if ([string]::IsNullOrWhiteSpace($NameSuffix)) { '' } else { "-$($NameSuffix.ToLower())" }
    $raw = $NameSuffix.ToLower()

    return [pscustomobject]@{
        coreResourceGroupName    = "rg-${n}-core-${env}${sfx}"
        networkResourceGroupName = "rg-${n}-network-${env}${sfx}"
        storageAccountName       = "st${n}${env}${raw}"
        keyVaultName             = "kv-${n}-${env}${sfx}"
        openAiAccountName        = "oai-${n}-${env}${sfx}"
        hubName                  = "hub-${n}-${env}${sfx}"
        projectName              = "proj-${n}-${env}${sfx}"
        managedIdentityName      = "mi-${n}-${env}${sfx}"
        vnetName                 = "vnet-${n}-${env}${sfx}"
        vmName                   = "vm-${n}-${env}${sfx}"
        lawWorkspaceName         = "law-${n}-${env}${sfx}"
    }
}

# ---------------------------------------------------------------------------
# Read-EnterpriseEnvironmentConfig
#   Loads configuration using a two-layer YAML merge strategy:
#     Layer 1 — variables/core.yaml      (workload-wide defaults)
#     Layer 2 — variables/<env>.yaml     (environment-specific overrides; wins on collision)
#
#   After merging, the function:
#     - Injects environmentSuffix as a config key
#     - Validates all required keys are present and non-empty
#     - Validates integer and numeric fields
#     - Appends computed Azure resource names to the returned object
#
#   Parameters
#     ScriptRoot        Directory containing this config.ps1 file; used to locate variables/
#     EnvironmentSuffix "dev" or "uat"
#     NameSuffix        Optional 4-char suffix appended to resource names for global uniqueness
#                       (deploy.ps1 derives this from the first 4 hex chars of the subscription ID)
#
#   Returns a pscustomobject.  Example property access:
#     $config.keyVaultName      → "kv-aistack3-dev-a1b2"
#     $config.openaiApiVersion  → "2025-01-01-preview"
# ---------------------------------------------------------------------------
function Read-EnterpriseEnvironmentConfig {
    param(
        [Parameter(Mandatory)] [string] $ScriptRoot,
        [Parameter(Mandatory)] [ValidateSet('dev', 'uat')] [string] $EnvironmentSuffix,
        [string] $NameSuffix = ''
    )

    if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
        throw 'ScriptRoot cannot be null or empty when loading environment configuration.'
    }

    $resolvedScriptRoot = (Resolve-Path -Path $ScriptRoot -ErrorAction Stop).Path

    # ---- Helper: parse a single YAML file into an ordered hashtable ----
    $parseYaml = {
        param([string]$YamlPath)
        $result = [ordered]@{}
        $inVariables = $false
        foreach ($line in Get-Content $YamlPath) {
            if ($line -match '^variables:') {
                $inVariables = $true
                continue
            }
            if ($inVariables -and $line -match '^\s{2}(\w+):\s+(.+)$') {
                $result[$Matches[1]] = Convert-ConfigScalar $Matches[2]
            }
        }
        return $result
    }

    # ---- Layer 1: shared values (common across all environments) ----
    $sharedYamlPath = Join-Path $resolvedScriptRoot "..\variables\core.yaml"
    if (-not (Test-Path $sharedYamlPath)) {
        throw "Core variables file not found: $sharedYamlPath"
    }
    $config = & $parseYaml $sharedYamlPath

    # ---- Layer 2: environment-specific overrides (wins on collision) ----
    $envYamlPath = Join-Path $resolvedScriptRoot "..\variables\$EnvironmentSuffix.yaml"
    if (-not (Test-Path $envYamlPath)) {
        throw "Environment variables file not found: $envYamlPath"
    }
    $envConfig = & $parseYaml $envYamlPath
    foreach ($key in $envConfig.Keys) {
        $config[$key] = $envConfig[$key]   # env layer wins on collision
    }

    # ---- Validate all required keys are present in the merged config ----
    $requiredKeys = @(
        'baseName',
        'location',
        'skuName',
        'containerName',
        'modelDeploymentName',
        'modelName',
        'modelVersion',
        'modelSkuName',
        'capacityK',
        'secondaryModelDeploymentName',
        'secondaryModelName',
        'secondaryModelVersion',
        'secondaryModelSkuName',
        'secondaryCapacityK',
        'openaiApiVersion',
        'mlApiVersion',
        'vmAdminUsername',
        'vmUseSpot',
        'vmSpotMaxPrice',
        'vmAutoShutdownEnabled',
        'vmAutoShutdownTime',
        'vmAutoShutdownTimeZone',
        'privateAiWorkspacesOnly',
        'enableAuditDiagnostics',
        'logAnalyticsRetentionDays',
        'logAnalyticsDailyQuotaGb',
        'adminObjectIds',
        'serviceConnection'
    )

    $missingKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $requiredKeys) {
        if (-not $config.Contains($key) -or [string]::IsNullOrWhiteSpace([string]$config[$key])) {
            $missingKeys.Add($key)
        }
    }

    if ($missingKeys.Count -gt 0) {
        throw "Missing required values after merging core.yaml + ${EnvironmentSuffix}.yaml: $($missingKeys -join ', ')"
    }

    # ---- Validate integer fields ----
    $integerKeys = @('capacityK', 'secondaryCapacityK', 'vmSpotMaxPrice', 'logAnalyticsRetentionDays')
    $invalidIntegerKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $integerKeys) {
        if ([string]$config[$key] -notmatch '^-?\d+$') {
            $invalidIntegerKeys.Add($key)
        }
    }

    if ($invalidIntegerKeys.Count -gt 0) {
        throw "Invalid integer values in merged config: $($invalidIntegerKeys -join ', ')"
    }

    if ([string]$config['logAnalyticsDailyQuotaGb'] -notmatch '^-?\d+(\.\d+)?$') {
        throw "Invalid numeric value 'logAnalyticsDailyQuotaGb' in merged config"
    }

    # ---- Inject environmentSuffix into the result ----
    $config['environmentSuffix'] = $EnvironmentSuffix

    # ---- Append computed resource names ----
    $resourceNames = Get-EnterpriseResourceNames -BaseName $config['baseName'] -EnvironmentSuffix $EnvironmentSuffix -NameSuffix $NameSuffix
    foreach ($property in $resourceNames.PSObject.Properties) {
        $config[$property.Name] = $property.Value
    }

    return [pscustomobject]$config
}
