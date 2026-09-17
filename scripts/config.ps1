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
#     BaseName          Short workload prefix (max 5-8 lowercase alphanumeric characters)
#     EnvironmentSuffix Environment token: "dev" or "uat"
#     NameSuffix        Optional 4-char subscription-derived suffix for global uniqueness
#
#   Returns a pscustomobject with properties:
#     coreResourceGroupName, networkResourceGroupName, storageAccountName,
#     keyVaultName, openAiAccountName, hubName, projectName,
#     hubManagedIdentityName, vmManagedIdentityName, automationManagedIdentityName,
#     automationAccountName, vnetName, vmName, lawWorkspaceName
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
        hubManagedIdentityName   = "mi-${n}-hub-${env}${sfx}"
        vmManagedIdentityName    = "mi-${n}-vm-${env}${sfx}"
        automationManagedIdentityName = "mi-${n}-automation-${env}${sfx}"
        automationAccountName    = "aa-${n}-${env}${sfx}"
        vmStartScheduleName      = 'start-vm-daily'
        rdpDeployerCleanupScheduleName = 'delete-rdp-deployer-weekly'
        legacyManagedIdentityName = "mi-${n}-${env}${sfx}"
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
#     $config.keyVaultName      → "kv-<baseName>-dev-a1b2"
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
        $currentKey = $null
        $currentList = $null
        $currentObj = $null

        foreach ($rawLine in Get-Content $YamlPath) {
            $line = $rawLine.TrimEnd()
            $trimmed = $line.Trim()
            if ($trimmed.StartsWith('#') -or $trimmed -eq '') { continue }

            if ($line -match '^variables:\s*(#.*)?$') {
                $inVariables = $true
                continue
            }
            if (-not $inVariables) { continue }

            # Top-level key: '  key: value' or '  key:'
            if ($line -match '^\s{2}(\w+):\s*(.*)$') {
                $key = $Matches[1]
                $rest = $Matches[2].Trim()

                $currentKey = $key
                $currentList = $null
                $currentObj = $null

                if ($rest -ne '' -and $rest -notmatch '^#') {
                    $restClean = $rest -replace '\s+#.*$', ''
                    if ($restClean.StartsWith('[') -and $restClean.EndsWith(']')) {
                        try {
                            $jsonArray = $restClean | ConvertFrom-Json
                            $result[$key] = $jsonArray
                        } catch {
                            $result[$key] = $restClean
                        }
                    } else {
                        $result[$key] = Convert-ConfigScalar $restClean
                    }
                } else {
                    $currentList = [System.Collections.Generic.List[object]]::new()
                    $result[$key] = $currentList
                }
                continue
            }

            # List item: '    - ...'
            if ($null -ne $currentKey -and $line -match '^\s{4}-\s*(.*)$') {
                $itemRest = $Matches[1].Trim() -replace '\s+#.*$', ''
                if ($null -eq $currentList) {
                    $currentList = [System.Collections.Generic.List[object]]::new()
                    $result[$currentKey] = $currentList
                }

                if ($itemRest -match '^(\w+):\s*(.*)$') {
                    $currentObj = [ordered]@{}
                    $propKey = $Matches[1]
                    $propVal = Convert-ConfigScalar $Matches[2]
                    $currentObj[$propKey] = $propVal
                    $currentList.Add($currentObj)
                } else {
                    $currentObj = $null
                    $scalarVal = Convert-ConfigScalar $itemRest
                    if ($scalarVal -ne '') {
                        $currentList.Add($scalarVal)
                    }
                }
                continue
            }

            # Sub-property in object list: '      prop: val'
            if ($null -ne $currentObj -and $line -match '^\s{6}(\w+):\s*(.*)$') {
                $propKey = $Matches[1]
                $propVal = Convert-ConfigScalar $Matches[2]
                $currentObj[$propKey] = $propVal
                continue
            }
        }
        return $result
    }

    # ---- Helper: ensure a local (untracked) YAML file exists, seeding it from its .example ----
    # variables/*.yaml holds user-specific configuration and is never committed. Only the
    # matching *.yaml.example files are tracked, so a fresh clone has to seed them once.
    # CI has no local file, so it supplies the full YAML content through an environment
    # variable (a secret or variable group), which is written to disk for this run only.
    $ensureLocalYaml = {
        param([string]$YamlPath, [string]$Description, [string]$ContentEnvVarName)

        if (Test-Path -LiteralPath $YamlPath -PathType Leaf) {
            return
        }

        $suppliedContent = [System.Environment]::GetEnvironmentVariable($ContentEnvVarName)
        if (-not [string]::IsNullOrWhiteSpace($suppliedContent)) {
            $yamlDirectory = Split-Path -Parent $YamlPath
            if (-not (Test-Path -LiteralPath $yamlDirectory)) {
                New-Item -ItemType Directory -Path $yamlDirectory -Force | Out-Null
            }
            Set-Content -LiteralPath $YamlPath -Value $suppliedContent -Encoding utf8NoBOM
            return
        }

        $examplePath = "$YamlPath.example"
        if (-not (Test-Path -LiteralPath $examplePath -PathType Leaf)) {
            throw "$Description not found: $YamlPath (and no $examplePath to seed it from)."
        }

        Copy-Item -LiteralPath $examplePath -Destination $YamlPath -Force
        throw @"
$Description was missing, so it was created from '$([System.IO.Path]::GetFileName($examplePath))'.

Open '$YamlPath', replace every <REPLACE_WITH_...> placeholder with your own values, and rerun.
Files under variables/ are intentionally untracked: never commit your configuration.
In CI, supply the full file content through the '$ContentEnvVarName' environment variable instead.
"@
    }

    # ---- Layer 1: shared values (common across all environments) ----
    $sharedYamlPath = Join-Path $resolvedScriptRoot "..\variables\core.yaml"
    & $ensureLocalYaml $sharedYamlPath 'Core variables file' 'AI_INFRA_CORE_YAML'
    $config = & $parseYaml $sharedYamlPath

    # ---- Layer 2: environment-specific overrides (wins on collision) ----
    $envYamlPath = Join-Path $resolvedScriptRoot "..\variables\$EnvironmentSuffix.yaml"
    & $ensureLocalYaml $envYamlPath "Environment variables file for '$EnvironmentSuffix'" 'AI_INFRA_ENV_YAML'
    $envConfig = & $parseYaml $envYamlPath
    if ($envConfig.Contains('environmentSuffix') -and $envConfig['environmentSuffix'] -ne $EnvironmentSuffix) {
        throw "environmentSuffix '$($envConfig['environmentSuffix'])' in $envYamlPath must match '$EnvironmentSuffix'"
    }
    foreach ($key in $envConfig.Keys) {
        $config[$key] = $envConfig[$key]   # env layer wins on collision
    }

    if (-not $config.Contains('vmPublicIpDnsNameLabel')) {
        $config['vmPublicIpDnsNameLabel'] = ''
    }

    if (-not $config.Contains('rdpAllowedIpCidrs')) {
        $config['rdpAllowedIpCidrs'] = @()
    }

    if (-not $config.Contains('rdpAllowedPublicIpAddress')) {
        $config['rdpAllowedPublicIpAddress'] = ''
    }

    $normalizeStringArray = {
        param([AllowNull()] [object] $RawValue)

        $quoteTrimChars = [char[]]@([char]39, [char]34)
        $values = [System.Collections.Generic.List[string]]::new()
        if ($null -eq $RawValue) {
            return @($values)
        }

        $items = @()
        if ($RawValue -is [string]) {
            $trimmed = $RawValue.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -eq '[]') {
                return @($values)
            }
            if ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) {
                try {
                    $items = @($trimmed | ConvertFrom-Json)
                } catch {
                    $items = @($trimmed.Trim('[]') -split ',' | ForEach-Object { $_.Trim().Trim($quoteTrimChars) })
                }
            } else {
                $items = @($trimmed -split ',' | ForEach-Object { $_.Trim() })
            }
        } elseif ($RawValue -is [System.Collections.IEnumerable] -and -not ($RawValue -is [string])) {
            $items = @($RawValue)
        } else {
            $items = @($RawValue)
        }

        foreach ($item in $items) {
            if ($null -eq $item) { continue }
            $value = [string]$item
            $value = $value.Trim().Trim($quoteTrimChars)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $values.Add($value)
            }
        }

        return @($values)
    }

    $normalizeIpv4SourceAddress = {
        param(
            [Parameter(Mandatory)] [string] $Value,
            [Parameter(Mandatory)] [string] $KeyName
        )

        $text = $Value.Trim()
        $parts = $text -split '/', 2
        $addressText = $parts[0]
        $prefixLength = if ($parts.Count -eq 2) { $parts[1] } else { $null }

        if ($addressText -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
            throw "Invalid IPv4 address or CIDR '$Value' for '$KeyName'. Use values such as 203.0.113.10 or 203.0.113.10/32."
        }
        foreach ($octet in ($addressText -split '\.')) {
            if ([int]$octet -lt 0 -or [int]$octet -gt 255) {
                throw "Invalid IPv4 address or CIDR '$Value' for '$KeyName'. Each octet must be 0-255."
            }
        }
        if ($null -eq $prefixLength) {
            return $addressText
        }
        if ($prefixLength -notmatch '^\d{1,2}$' -or [int]$prefixLength -lt 0 -or [int]$prefixLength -gt 32) {
            throw "Invalid CIDR prefix '$prefixLength' for '$KeyName'. IPv4 prefixes must be 0-32."
        }

        return "$addressText/$([int]$prefixLength)"
    }

    $rdpAllowedIpCidrs = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace([string]$config['rdpAllowedPublicIpAddress'])) {
        $rdpAllowedIpCidrs.Add((& $normalizeIpv4SourceAddress ([string]$config['rdpAllowedPublicIpAddress']) 'rdpAllowedPublicIpAddress'))
    }
    foreach ($cidr in (& $normalizeStringArray $config['rdpAllowedIpCidrs'])) {
        $normalizedCidr = & $normalizeIpv4SourceAddress $cidr 'rdpAllowedIpCidrs'
        if (-not $rdpAllowedIpCidrs.Contains($normalizedCidr)) {
            $rdpAllowedIpCidrs.Add($normalizedCidr)
        }
    }
    $config['rdpAllowedIpCidrs'] = @($rdpAllowedIpCidrs)

    # ---- Helper: normalize actor inputs (users/admins) into structured objects ----
    $normalizeActorArray = {
        param(
            [AllowNull()] [object] $RawValue,
            [Parameter(Mandatory)] [string] $ActorRoleName
        )

        $actors = [System.Collections.Generic.List[pscustomobject]]::new()
        if ($null -eq $RawValue) {
            return @($actors)
        }

        $items = @()
        if ($RawValue -is [string]) {
            $trimmed = $RawValue.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -eq '[]') {
                return @($actors)
            }
            if ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) {
                try {
                    $items = @($trimmed | ConvertFrom-Json)
                } catch {
                    $items = @($trimmed.Trim('[]') -split ',' | ForEach-Object { $_.Trim().Trim("'`"") })
                }
            } else {
                $items = @($trimmed -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
            }
        } elseif ($RawValue -is [System.Collections.IEnumerable] -and -not ($RawValue -is [string])) {
            $items = @($RawValue)
        } else {
            $items = @($RawValue)
        }

        foreach ($item in $items) {
            if ($null -eq $item) { continue }
            $objectId = ''
            $principalType = 'User'

            if ($item -is [string]) {
                $objectId = $item.Trim().Trim("'`"")
            } elseif ($item -is [System.Collections.IDictionary]) {
                $objectId = if ($item.Contains('objectId')) { [string]$item['objectId'] } elseif ($item.Contains('id')) { [string]$item['id'] } else { '' }
                if ($item.Contains('principalType') -and -not [string]::IsNullOrWhiteSpace([string]$item['principalType'])) {
                    $principalType = [string]$item['principalType']
                } elseif ($item.Contains('type') -and -not [string]::IsNullOrWhiteSpace([string]$item['type'])) {
                    $principalType = [string]$item['type']
                }
            } elseif ($item -is [pscustomobject]) {
                $objectId = if ($item.PSObject.Properties['objectId']) { [string]$item.objectId } elseif ($item.PSObject.Properties['id']) { [string]$item.id } else { '' }
                if ($item.PSObject.Properties['principalType'] -and -not [string]::IsNullOrWhiteSpace([string]$item.principalType)) {
                    $principalType = [string]$item.principalType
                } elseif ($item.PSObject.Properties['type'] -and -not [string]::IsNullOrWhiteSpace([string]$item.type)) {
                    $principalType = [string]$item.type
                }
            }

            $objectId = $objectId.Trim()
            if ([string]::IsNullOrWhiteSpace($objectId) -or $objectId.StartsWith('<REPLACE')) {
                continue
            }

            if ($objectId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                throw "$ActorRoleName actor contains '$objectId', which is not a valid Entra GUID."
            }

            if ($principalType -notin @('User', 'Group', 'ServicePrincipal')) {
                throw "$ActorRoleName actor '$objectId' has invalid principalType '$principalType'. Allowed values: User, Group, ServicePrincipal."
            }

            $actors.Add([pscustomobject]@{
                objectId = $objectId
                principalType = $principalType
            })
        }

        return @($actors)
    }

    # ---- Validate all required keys are present in the merged config ----
    $requiredKeys = @(
        'baseName',
        'location',
        'vnetAddressSpace',
        'servicesSubnetAddressPrefix',
        'vmSubnetAddressPrefix',
        'vmAcceleratedNetworking',
        'skuName',
        'storageAccessTier',
        'containerName',
        'storageBlobSoftDeleteRetentionDays',
        'storageContainerSoftDeleteRetentionDays',
        'keyVaultSoftDeleteRetentionDays',
        'modelDeployments',
        'openaiApiVersion',
        'mlApiVersion',
        'vmAdminUsername',
        'vmSize',
        'vmImagePublisher',
        'vmImageOffer',
        'vmImageSku',
        'vmImageVersion',
        'vmOsDiskStorageAccountType',
        'vmUseSpot',
        'vmSpotMaxPrice',
        'vmAutoShutdownEnabled',
        'vmAutoShutdownTime',
        'vmAutoShutdownTimeZone',
        'vmGuestTimeZone',
        'deployStorage',
        'deployLogAnalytics',
        'deployAiFoundry',
        'deployVm',
        'deployAutomation',
        'automationRuntimeVersion',
        'automationAzVersion',
        'vmStartScheduleEnabled',
        'vmStartScheduleTime',
        'vmStartScheduleTimeZone',
        'rdpDeployerCleanupScheduleEnabled',
        'rdpDeployerCleanupScheduleTime',
        'rdpDeployerCleanupScheduleTimeZone',
        'privateAiWorkspacesOnly',
        'enableAuditDiagnostics',
        'logAnalyticsRetentionDays',
        'logAnalyticsDailyQuotaGb',
        'serviceConnection',
        'githubAzureClientIdSecretName',
        'githubAzureTenantIdSecretName',
        'githubAzureSubscriptionIdSecretName'
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

    # ---- Normalize admin and user actor arrays ----
    $rawAdmin = if ($config.Contains('admin')) { $config['admin'] } elseif ($config.Contains('admins')) { $config['admins'] } elseif ($config.Contains('adminObjectIds')) { $config['adminObjectIds'] } else { $null }
    $rawUser = if ($config.Contains('user')) { $config['user'] } elseif ($config.Contains('users')) { $config['users'] } elseif ($config.Contains('userObjectIds')) { $config['userObjectIds'] } else { $null }

    $adminActors = & $normalizeActorArray $rawAdmin 'admin'
    $userActors = & $normalizeActorArray $rawUser 'user'

    $config['admin'] = $adminActors
    $config['user'] = $userActors
    $config['adminActors'] = $adminActors
    $config['userActors'] = $userActors
    $config['adminObjectIds'] = ($adminActors | ForEach-Object { $_.objectId }) -join ','

    # ---- Validate integer fields ----
    $integerKeys = @(
        'storageBlobSoftDeleteRetentionDays',
        'storageContainerSoftDeleteRetentionDays',
        'keyVaultSoftDeleteRetentionDays',
        'vmSpotMaxPrice',
        'logAnalyticsRetentionDays'
    )
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
    if ([decimal]$config['logAnalyticsDailyQuotaGb'] -ne -1 -and [decimal]$config['logAnalyticsDailyQuotaGb'] -le 0) {
        throw "logAnalyticsDailyQuotaGb must be -1 or a positive number"
    }

    $allowedValues = @{
        skuName = @('Standard_LRS', 'Standard_GRS', 'Standard_ZRS')
        storageAccessTier = @('Hot', 'Cool')
        vmOsDiskStorageAccountType = @('Standard_LRS', 'StandardSSD_LRS', 'Premium_LRS')
    }
    foreach ($key in $allowedValues.Keys) {
        if ([string]$config[$key] -notin $allowedValues[$key]) {
            throw "Invalid value '$($config[$key])' for '$key'. Allowed values: $($allowedValues[$key] -join ', ')"
        }
    }

    foreach ($key in @('githubAzureClientIdSecretName', 'githubAzureTenantIdSecretName', 'githubAzureSubscriptionIdSecretName')) {
        if ([string]$config[$key] -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid GitHub secret name '$($config[$key])' for '$key'. Use letters, numbers, and underscores, starting with a letter or underscore."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$config['vmPublicIpDnsNameLabel'])) {
        if ([string]$config['vmPublicIpDnsNameLabel'] -notmatch '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$') {
            throw "Invalid DNS name label '$($config['vmPublicIpDnsNameLabel'])' for 'vmPublicIpDnsNameLabel'. Use 1-63 lowercase letters, numbers, or hyphens, starting and ending with a letter or number."
        }
    }

    $booleanKeys = @(
        'vmAcceleratedNetworking',
        'vmUseSpot',
        'vmAutoShutdownEnabled',
        'deployStorage',
        'deployLogAnalytics',
        'deployAiFoundry',
        'deployVm',
        'deployAutomation',
        'vmStartScheduleEnabled',
        'rdpDeployerCleanupScheduleEnabled',
        'privateAiWorkspacesOnly',
        'enableAuditDiagnostics'
    )
    foreach ($key in $booleanKeys) {
        if ([string]$config[$key] -notin @('true', 'false')) {
            throw "Invalid boolean value '$($config[$key])' for '$key'. Allowed values: true, false"
        }
    }

    # ---- Validate deployment-flag dependencies ----
    # Key Vault, the virtual network, Azure OpenAI, and the managed identities have no flag:
    # they hold deployment state or are required by every other component, so they are never removed.
    $isFlagEnabled = { param([string]$Key) [string]$config[$Key] -eq 'true' }

    if ((& $isFlagEnabled 'deployAiFoundry') -and -not (& $isFlagEnabled 'deployStorage')) {
        throw "deployAiFoundry requires deployStorage because the AI Hub workspace needs a backing Storage account."
    }
    if ((& $isFlagEnabled 'enableAuditDiagnostics') -and -not (& $isFlagEnabled 'deployLogAnalytics')) {
        throw "enableAuditDiagnostics requires deployLogAnalytics because diagnostics need a workspace destination."
    }
    if ((& $isFlagEnabled 'deployAutomation') -and -not (& $isFlagEnabled 'deployVm')) {
        throw "deployAutomation requires deployVm because the start-vm runbook is scoped to the jumpbox VM."
    }
    if ((& $isFlagEnabled 'vmStartScheduleEnabled') -and -not (& $isFlagEnabled 'deployAutomation')) {
        throw "vmStartScheduleEnabled requires deployAutomation because the schedule lives in the Automation Account."
    }
    if ((& $isFlagEnabled 'rdpDeployerCleanupScheduleEnabled') -and -not (& $isFlagEnabled 'deployAutomation')) {
        throw "rdpDeployerCleanupScheduleEnabled requires deployAutomation because the schedule lives in the Automation Account."
    }
    if ((& $isFlagEnabled 'vmAutoShutdownEnabled') -and -not (& $isFlagEnabled 'deployVm')) {
        throw "vmAutoShutdownEnabled requires deployVm because the schedule targets the jumpbox VM."
    }

    if ([int]$config['storageBlobSoftDeleteRetentionDays'] -lt 0 -or [int]$config['storageBlobSoftDeleteRetentionDays'] -gt 365) {
        throw "storageBlobSoftDeleteRetentionDays must be 0-365"
    }
    if ([int]$config['storageContainerSoftDeleteRetentionDays'] -lt 0 -or [int]$config['storageContainerSoftDeleteRetentionDays'] -gt 365) {
        throw "storageContainerSoftDeleteRetentionDays must be 0-365"
    }
    if ([int]$config['keyVaultSoftDeleteRetentionDays'] -lt 7 -or [int]$config['keyVaultSoftDeleteRetentionDays'] -gt 90) {
        throw "keyVaultSoftDeleteRetentionDays must be 7-90"
    }
    if ([int]$config['logAnalyticsRetentionDays'] -lt 30 -or [int]$config['logAnalyticsRetentionDays'] -gt 730) {
        throw "logAnalyticsRetentionDays must be 30-730"
    }
    $modelDeployments = @($config['modelDeployments'])
    if ($modelDeployments.Count -lt 2) {
        throw 'modelDeployments must contain at least two entries because the chat app uses primary and secondary deployments'
    }
    $modelDeploymentNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $normalizedModelDeployments = [System.Collections.Generic.List[object]]::new()
    foreach ($modelDeployment in $modelDeployments) {
        $modelValues = [ordered]@{}
        foreach ($propertyName in @('deploymentName', 'modelName', 'modelVersion', 'skuName', 'capacityK')) {
            $propertyValue = if ($modelDeployment -is [System.Collections.IDictionary] -and $modelDeployment.Contains($propertyName)) {
                $modelDeployment[$propertyName]
            } elseif ($modelDeployment.PSObject.Properties[$propertyName]) {
                $modelDeployment.$propertyName
            } else {
                $null
            }
            if ([string]::IsNullOrWhiteSpace([string]$propertyValue)) {
                throw "Each modelDeployments entry must define deploymentName, modelName, modelVersion, skuName, and capacityK"
            }
            $modelValues[$propertyName] = $propertyValue
        }
        if ([string]$modelValues.deploymentName -notmatch '^[A-Za-z0-9._-]+$') {
            throw "Invalid model deployment name '$($modelValues.deploymentName)'"
        }
        if (-not $modelDeploymentNames.Add([string]$modelValues.deploymentName)) {
            throw "modelDeployments contains duplicate deployment name '$($modelValues.deploymentName)'"
        }
        if ([string]$modelValues.capacityK -notmatch '^\d+$' -or [int]$modelValues.capacityK -lt 1) {
            throw "Model deployment '$($modelValues.deploymentName)' capacityK must be a positive integer"
        }
        $normalizedModelDeployments.Add([pscustomobject]$modelValues)
    }
    $config['modelDeployments'] = @($normalizedModelDeployments)
    if ([int]$config['vmSpotMaxPrice'] -lt -1) {
        throw "vmSpotMaxPrice must be -1 or a nonnegative whole number"
    }
    if ([string]$config['vmAutoShutdownTime'] -notmatch '^([01]\d|2[0-3])[0-5]\d$') {
        throw "vmAutoShutdownTime must use 24-hour HHmm format"
    }
    if ([string]$config['vmStartScheduleTime'] -notmatch '^([01]\d|2[0-3])[0-5]\d$') {
        throw "vmStartScheduleTime must use 24-hour HHmm format"
    }
    if ([string]$config['rdpDeployerCleanupScheduleTime'] -notmatch '^([01]\d|2[0-3])[0-5]\d$') {
        throw "rdpDeployerCleanupScheduleTime must use 24-hour HHmm format"
    }
    if ([string]$config['automationRuntimeVersion'] -ne '7.4') {
        throw "automationRuntimeVersion must be 7.4"
    }
    if ([string]$config['automationAzVersion'] -notmatch '^\d+\.\d+\.\d+$') {
        throw "automationAzVersion must use semantic version format"
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
