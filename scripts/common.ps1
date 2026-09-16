# common.ps1 — Shared utility functions sourced by deploy.ps1, test.ps1, and cleanup.ps1.

# --- Local, git-ignored file logging (.logs/) ---------------------------------------------------
# Mirrors the .local/ convention: a repo-root '.logs' folder that never leaves the workstation.
# Only the same curated messages already shown on the console (Write-Task/Write-Exists/
# Write-Needed/Write-Info) are persisted — never raw Azure CLI/API responses — so the log stays
# small and free of secrets by construction. As defense-in-depth, secret-shaped substrings are
# still redacted before a line is ever written to disk. Rolls over at 5 MB into exactly two files
# (current + .old); nothing older is ever retained.
$script:LogFilePath = $null
$script:LogInitialized = $false
$script:LogMaxBytes = 5MB
$script:LogDirName = '.logs'
$script:LogFileName = 'ai-infra.log'
$script:LogFileNameOld = 'ai-infra.log.old'
$script:TimingInitialized = $false
$script:TimingSummaryWritten = $false
$script:TimingStartedAt = $null
$script:TimingCurrentOperation = $null
$script:TimingRecords = $null

# Patterns for secret-shaped substrings to scrub before persisting a log line. Applied even
# though callers should never pass secrets to these functions, as a second line of defense.
$script:LogRedactionPatterns = @(
    '(?i)((?:password|passwd|pwd|secret|token|apikey|api[_-]?key|connectionstring|client[_-]?secret)\s*[:=]\s*)(\S+)',
    '(?i)(Authorization:\s*Bearer\s+)(\S+)',
    '(?i)(\bBearer\s+)([A-Za-z0-9._~+/=-]{10,})',
    '(?i)(\?[^"''\s]*\bsig=)([^"''&\s]+)'
)

function Protect-LogMessage {
    param([AllowNull()] [string] $Message)

    if ([string]::IsNullOrEmpty($Message)) {
        return $Message
    }

    $redacted = $Message
    foreach ($pattern in $script:LogRedactionPatterns) {
        $redacted = [regex]::Replace($redacted, $pattern, '$1***REDACTED***')
    }
    return $redacted
}

function Invoke-LogRollover {
    if (-not (Test-Path -LiteralPath $script:LogFilePath)) {
        return
    }

    $currentSize = (Get-Item -LiteralPath $script:LogFilePath).Length
    if ($currentSize -lt $script:LogMaxBytes) {
        return
    }

    $logDir = Split-Path -Parent $script:LogFilePath
    $oldPath = Join-Path $logDir $script:LogFileNameOld
    Move-Item -LiteralPath $script:LogFilePath -Destination $oldPath -Force
}

function Write-LogEntry {
    param(
        [Parameter(Mandatory)] [string] $Level,
        [AllowNull()] [string] $Message
    )

    if (-not $script:LogInitialized -or -not $script:LogFilePath) {
        return
    }

    try {
        Invoke-LogRollover
        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $flatMessage = ($Message -replace '\r?\n', ' | ')
        $safeMessage = Protect-LogMessage -Message $flatMessage
        Add-Content -LiteralPath $script:LogFilePath -Value "[$timestamp] [$Level] $safeMessage" -Encoding utf8
    } catch {
        # Logging must never break the calling script.
    }
}

function Initialize-ScriptLogging {
    param(
        [Parameter(Mandatory)] [string] $ScriptRoot,
        [Parameter(Mandatory)] [string] $ScriptName
    )

    if ($script:LogInitialized) {
        return
    }

    try {
        $repoRoot = Split-Path -Parent $ScriptRoot
        $logDir = Join-Path $repoRoot $script:LogDirName
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        $script:LogFilePath = Join-Path $logDir $script:LogFileName
        $script:LogInitialized = $true
        $script:TimingInitialized = $true
        $script:TimingSummaryWritten = $false
        $script:TimingStartedAt = [DateTimeOffset]::Now
        $script:TimingCurrentOperation = $null
        $script:TimingRecords = [System.Collections.Generic.List[object]]::new()
        Write-LogEntry -Level 'START' -Message "==== $ScriptName started (PID $PID) ===="
    } catch {
        # Logging is best-effort; never fail script startup because of it.
        $script:LogInitialized = $false
        $script:LogFilePath = $null
    }
}

function Format-TimingDuration {
    param([Parameter(Mandatory)] [TimeSpan] $Duration)

    return '{0:00}:{1:00}:{2:00}.{3:000}' -f [Math]::Floor($Duration.TotalHours), $Duration.Minutes, $Duration.Seconds, $Duration.Milliseconds
}

function Get-TimingOperationKind {
    param([AllowNull()] [string] $Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return 'Step'
    }

    if ($Message -match '^\s*(Step\s+\d+/\d+|Stage\b|Phase\b)') {
        return 'Stage'
    }

    if ($Message -match '(?i)\b(resource group|storage account|key vault|openai account|cognitive services account|workspace|public ip|virtual machine|vm\b|managed identity|role assignment|runbook|schedule|private endpoint|diagnostic setting|os disk|network interface|\bnic\b|network security group|\bnsg\b|container)\b') {
        return 'Resource'
    }

    return 'Step'
}

function Complete-CurrentTimingOperation {
    param([string] $Status = 'completed')

    if (-not $script:TimingInitialized -or $null -eq $script:TimingCurrentOperation -or $null -eq $script:TimingRecords) {
        return
    }

    $completedAt = [DateTimeOffset]::Now
    $startedAt = [DateTimeOffset]$script:TimingCurrentOperation.StartedAt
    $script:TimingRecords.Add([pscustomobject]@{
        Kind = [string]$script:TimingCurrentOperation.Kind
        Operation = [string]$script:TimingCurrentOperation.Operation
        Status = $Status
        Started = $startedAt.ToString('HH:mm:ss')
        Completed = $completedAt.ToString('HH:mm:ss')
        Duration = Format-TimingDuration -Duration ($completedAt - $startedAt)
    })
    $script:TimingCurrentOperation = $null
}

function Start-TimingOperation {
    param([Parameter(Mandatory)] [string] $Message)

    if (-not $script:TimingInitialized) {
        return
    }

    Complete-CurrentTimingOperation -Status 'completed'
    $script:TimingCurrentOperation = [pscustomobject]@{
        Kind = Get-TimingOperationKind -Message $Message
        Operation = $Message.Trim()
        StartedAt = [DateTimeOffset]::Now
    }
}

function Write-ScriptTimingSummary {
    param([string] $Status = 'completed')

    if (-not $script:TimingInitialized -or $script:TimingSummaryWritten -or $null -eq $script:TimingStartedAt) {
        return
    }

    Complete-CurrentTimingOperation -Status $Status
    $completedAt = [DateTimeOffset]::Now
    $totalDuration = $completedAt - ([DateTimeOffset]$script:TimingStartedAt)

    $rows = @()
    if ($null -ne $script:TimingRecords) {
        $rows += @($script:TimingRecords)
    }
    $rows += [pscustomobject]@{
        Kind = 'Total'
        Operation = 'Total script execution time'
        Status = $Status
        Started = ([DateTimeOffset]$script:TimingStartedAt).ToString('HH:mm:ss')
        Completed = $completedAt.ToString('HH:mm:ss')
        Duration = Format-TimingDuration -Duration $totalDuration
    }

    $summary = ($rows | Format-Table -AutoSize | Out-String -Width 240).TrimEnd()

    Write-Host ''
    Write-Host 'Execution timing summary:' -ForegroundColor Cyan
    Write-Host $summary -ForegroundColor DarkCyan

    Write-LogEntry -Level 'TIME' -Message 'Execution timing summary:'
    foreach ($line in ($summary -split '\r?\n')) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-LogEntry -Level 'TIME' -Message $line
        }
    }

    $script:TimingSummaryWritten = $true
}

function Complete-ScriptLogging {
    param([string] $Status = 'completed')
    Write-ScriptTimingSummary -Status $Status
    Write-LogEntry -Level 'END' -Message "==== script $Status ===="
}

function Write-Task {
    param([string]$Message)
    Start-TimingOperation -Message $Message
    Write-Host $Message -ForegroundColor Blue
    Write-LogEntry -Level 'TASK' -Message $Message
}

function Write-Exists {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
    Write-LogEntry -Level 'OK' -Message $Message
}

function Write-Needed {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
    Write-LogEntry -Level 'WARN' -Message $Message
}

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor DarkGray
    Write-LogEntry -Level 'INFO' -Message $Message
}

function Wait-WithBackoff {
    param(
        [Parameter(Mandatory)] [scriptblock] $Condition,
        [int] $MaxWaitSeconds = 600,
        [int] $InitialDelaySeconds = 2,
        [int] $MaxDelaySeconds = 30,
        [string] $OperationName = 'Operation'
    )

    $elapsed = 0
    $currentDelay = $InitialDelaySeconds
    $startTime = Get-Date

    while ($elapsed -lt $MaxWaitSeconds) {
        try {
            if (& $Condition) {
                return $true
            }
        } catch {
            Write-Info "  Transient error while checking condition: $_"
        }

        $remaining = $MaxWaitSeconds - $elapsed
        if ($remaining -le 0) {
            break
        }

        $waitTime = [Math]::Min($currentDelay, $remaining)
        Write-Info "  Waiting... ($($MaxWaitSeconds - $elapsed) seconds remaining, next check in ${waitTime}s)"
        Start-Sleep -Seconds $waitTime

        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
        $currentDelay = [Math]::Min($currentDelay * 1.5, $MaxDelaySeconds)
    }

    return $false
}

function Remove-AzureResource {
    param(
        [Parameter(Mandatory)] [string] $ResourceType,
        [Parameter(Mandatory)] [string] $ResourceId,
        [Parameter(Mandatory)] [string[]] $CommandArgs
    )

    Write-Task "Deleting $ResourceType '$ResourceId'..."
    try {
        $output = az @CommandArgs --yes 2>&1
        Write-Exists "  $ResourceType '$ResourceId' deleted."
        return $true
    } catch {
        Write-Needed "  Error: failed to delete $ResourceType '$ResourceId': $_"
        return $false
    }
}

function Get-AzureResourcesByFilter {
    param(
        [Parameter(Mandatory)] [string] $Filter,
        [string] $SubscriptionId
    )

    try {
        $listArgs = @('resource', 'list', '--query', $Filter, '--output', 'json')
        if ($SubscriptionId) {
            $listArgs += @('--subscription', $SubscriptionId)
        }
        $resourcesJson = az @listArgs 2>&1
        if ($resourcesJson) {
            return ($resourcesJson | ConvertFrom-Json)
        }
        return @()
    } catch {
        Write-Info "  Warning: failed to query resources: $_"
        return @()
    }
}

function Update-BicepCli {
    $env:AZURE_BICEP_USE_BINARY_FROM_PATH = 'false'

    Write-Task 'Checking Azure Bicep CLI version...'
    $installedOutput = (az bicep version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        Write-Needed '  Bicep CLI is not installed. Installing the latest version...'
        az bicep install --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to install the Bicep CLI through Azure CLI.'
        }
        $installedOutput = (az bicep version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw 'Bicep CLI installation completed but its version could not be read.'
        }
    }

    $installedMatch = [regex]::Match($installedOutput, 'Bicep CLI version\s+(\d+\.\d+\.\d+)')
    if (-not $installedMatch.Success) {
        throw "Could not parse the installed Bicep CLI version from: $installedOutput"
    }
    $installedVersion = [version]$installedMatch.Groups[1].Value

    $latestRaw = az bicep list-versions --query '[0]' --output tsv --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($latestRaw)) {
        throw 'Could not determine the latest available Bicep CLI version.'
    }
    $latestVersion = [version]$latestRaw.Trim().TrimStart('v')

    if ($installedVersion -lt $latestVersion) {
        Write-Needed "  Upgrading Bicep CLI from $installedVersion to $latestVersion..."
        az bicep upgrade --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to upgrade the Bicep CLI to $latestVersion."
        }

        $verifiedOutput = (az bicep version 2>&1 | Out-String).Trim()
        $verifiedMatch = [regex]::Match($verifiedOutput, 'Bicep CLI version\s+(\d+\.\d+\.\d+)')
        if ($LASTEXITCODE -ne 0 -or -not $verifiedMatch.Success -or [version]$verifiedMatch.Groups[1].Value -lt $latestVersion) {
            throw "Bicep CLI upgrade did not produce the expected version $latestVersion."
        }
        Write-Exists "  Bicep CLI upgraded to $latestVersion."
    } else {
        Write-Exists "  Bicep CLI $installedVersion is current."
    }
}

# ---------------------------------------------------------------------------
# Register-RequiredResourceProviders
#   Checks the registration state of every Azure resource provider namespace
#   used by the bicep templates in this repo, and registers any that are
#   NotRegistered. Waits (with backoff) for registration to finish so the
#   subsequent deployment doesn't fail with a "MissingSubscriptionRegistration"
#   error.
#
#   Parameters
#     SubscriptionId   Subscription to check/register providers against
#     ProviderNamespaces  Optional override of the namespace list
# ---------------------------------------------------------------------------
function Register-RequiredResourceProviders {
    param(
        [Parameter(Mandatory)] [string] $SubscriptionId,
        [string[]] $ProviderNamespaces = @(
            'Microsoft.Resources',
            'Microsoft.Authorization',
            'Microsoft.ManagedIdentity',
            'Microsoft.KeyVault',
            'Microsoft.Storage',
            'Microsoft.Network',
            'Microsoft.Compute',
            'Microsoft.CognitiveServices',
            'Microsoft.MachineLearningServices',
            'Microsoft.OperationalInsights',
            'Microsoft.Insights',
            'Microsoft.DevTestLab',
            'Microsoft.Automation'
        )
    )

    Write-Task 'Checking required Azure resource provider registrations...'

    $providersPendingRegistration = [System.Collections.Generic.List[string]]::new()

    foreach ($namespace in $ProviderNamespaces) {
        $state = az provider show --namespace $namespace --subscription $SubscriptionId --query registrationState --output tsv 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($state)) {
            Write-Info "  Warning: could not read registration state for '$namespace' (non-fatal)."
            continue
        }

        if ($state -eq 'Registered') {
            Write-Exists "  $namespace already registered."
        } else {
            Write-Needed "  $namespace is '$state' - registering..."
            az provider register --namespace $namespace --subscription $SubscriptionId --wait --output none 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Exists "  $namespace registration requested."
            } else {
                Write-Info "  Warning: failed to request registration for '$namespace' (non-fatal)."
            }
            $providersPendingRegistration.Add($namespace)
        }
    }

    foreach ($namespace in $providersPendingRegistration) {
        $isRegistered = Wait-WithBackoff -OperationName "Registering $namespace" -MaxWaitSeconds 300 -Condition {
            $state = az provider show --namespace $namespace --subscription $SubscriptionId --query registrationState --output tsv 2>$null
            return $state -eq 'Registered'
        }

        if ($isRegistered) {
            Write-Exists "  $namespace registration completed."
        } else {
            Write-Info "  Warning: $namespace registration did not complete within the timeout (non-fatal, deployment may fail)."
        }
    }
}

# ---------------------------------------------------------------------------
# Get-EffectiveRoleAssignmentWriteRole
#   Returns the name of the privileged role ('Owner' or 'User Access
#   Administrator') that is effective for the supplied principal at the
#   supplied subscription scope, including assignments inherited from a
#   management group or the root scope. Returns an empty string when neither
#   role is effective.
# ---------------------------------------------------------------------------
function Get-EffectiveRoleAssignmentWriteRole {
    param(
        [Parameter(Mandatory)] [string] $PrincipalObjectId,
        [Parameter(Mandatory)] [string] $SubscriptionScope
    )

    $roleNames = az role assignment list `
        --assignee $PrincipalObjectId `
        --scope $SubscriptionScope `
        --include-inherited `
        --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='User Access Administrator'].roleDefinitionName" `
        --output tsv 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($roleNames)) {
        return ''
    }

    return (@($roleNames -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0]).Trim()
}

# ---------------------------------------------------------------------------
# Initialize-RoleAssignmentWritePermission
#   Guarantees that the deploying identity can create Azure RBAC role
#   assignments at subscription scope, which main.bicep requires.
#
#   Escalation order (each step is skipped when the previous one succeeded):
#     1. Detect  — read effective Owner / User Access Administrator roles.
#     2. Grant   — self-assign 'User Access Administrator' at subscription
#                  scope. Succeeds when the identity already holds
#                  role-assignment write at a higher scope.
#     3. Elevate — interactive users only: call the Entra elevateAccess API,
#                  which grants User Access Administrator at root scope to an
#                  Entra Global Administrator, then retry step 2.
#     4. Verify  — re-read effective roles with backoff (RBAC is eventually
#                  consistent).
#
#   Returns $true when role-assignment write is effective, $false otherwise.
#   The caller is responsible for aborting the deployment on $false.
#
#   Parameters
#     PrincipalObjectId   Object ID of the deploying user or service principal
#     PrincipalType       'User' or 'ServicePrincipal'
#     SubscriptionId      Target subscription
#     SkipElevation       Suppress steps 2-3 (CI, or -SkipRoleElevation)
# ---------------------------------------------------------------------------
function Initialize-RoleAssignmentWritePermission {
    param(
        [Parameter(Mandatory)] [string] $PrincipalObjectId,
        [Parameter(Mandatory)] [string] $PrincipalType,
        [Parameter(Mandatory)] [string] $SubscriptionId,
        [bool] $SkipElevation = $false
    )

    $subscriptionScope = "/subscriptions/$SubscriptionId"

    Write-Task 'Verifying deploying identity has role-assignment write permission...'
    $effectiveRole = Get-EffectiveRoleAssignmentWriteRole -PrincipalObjectId $PrincipalObjectId -SubscriptionScope $subscriptionScope
    if (-not [string]::IsNullOrWhiteSpace($effectiveRole)) {
        Write-Exists "  Identity has '$effectiveRole' at subscription scope — role-assignment write confirmed."
        return $true
    }

    if ($SkipElevation) {
        Write-Info '  Role-assignment write is missing and self-elevation is disabled for this run.'
        return $false
    }

    Write-Needed "  Identity lacks 'Owner'/'User Access Administrator' at '$subscriptionScope' — attempting automatic remediation."

    # ---- Step 2: self-grant User Access Administrator at subscription scope ----
    Write-Task "  Attempting to grant 'User Access Administrator' at subscription scope..."
    $grantOutput = az role assignment create `
        --role 'User Access Administrator' `
        --assignee-object-id $PrincipalObjectId `
        --assignee-principal-type $PrincipalType `
        --scope $subscriptionScope `
        --output none 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Exists '  Role assignment created.'
    } else {
        Write-Info "  Self-grant was refused: $((($grantOutput | Out-String).Trim() -split '\r?\n')[0])"

        # ---- Step 3: Entra elevateAccess (Global Administrators only) ----
        if ($PrincipalType -ne 'User') {
            Write-Info '  Skipping Entra access elevation because the deploying identity is not an interactive user.'
        } else {
            Write-Task '  Attempting Entra "Access management for Azure resources" elevation...'
            $elevateOutput = az rest `
                --method post `
                --url 'https://management.azure.com/providers/Microsoft.Authorization/elevateAccess?api-version=2016-07-01' `
                --output none 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Exists '  Elevation succeeded (root-scope User Access Administrator granted).'
                Start-Sleep -Seconds 10
                Write-Task "  Retrying the 'User Access Administrator' grant at subscription scope..."
                az role assignment create `
                    --role 'User Access Administrator' `
                    --assignee-object-id $PrincipalObjectId `
                    --assignee-principal-type $PrincipalType `
                    --scope $subscriptionScope `
                    --output none 2>&1 | Out-Null
            } else {
                Write-Info "  Elevation was refused: $((($elevateOutput | Out-String).Trim() -split '\r?\n')[0])"
            }
        }
    }

    # ---- Step 4: verify with backoff, because RBAC propagation is delayed ----
    Write-Task '  Waiting for the role assignment to become effective...'
    $granted = Wait-WithBackoff -OperationName 'Role assignment propagation' -MaxWaitSeconds 120 -Condition {
        -not [string]::IsNullOrWhiteSpace((Get-EffectiveRoleAssignmentWriteRole -PrincipalObjectId $PrincipalObjectId -SubscriptionScope $subscriptionScope))
    }

    if ($granted) {
        $effectiveRole = Get-EffectiveRoleAssignmentWriteRole -PrincipalObjectId $PrincipalObjectId -SubscriptionScope $subscriptionScope
        Write-Exists "  Identity now has '$effectiveRole' at subscription scope — role-assignment write confirmed."
        return $true
    }

    return $false
}

function Remove-ResourceGroupLocks {
    param(
        [Parameter(Mandatory)] [string] $ResourceGroupName
    )

    Write-Task "Checking for delete locks on resource group '$ResourceGroupName'..."
    try {
        $locks = az lock list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
        if ($locks -and $locks.Count -gt 0) {
            foreach ($lock in $locks) {
                if ($lock.properties.level -eq 'CanNotDelete') {
                    Write-Needed "  Found delete lock '$($lock.name)' — removing..."
                    az lock delete --name $lock.name --resource-group $ResourceGroupName
                    Write-Exists "  Delete lock removed."
                }
            }
        } else {
            Write-Exists "  No delete locks found."
        }
    } catch {
        Write-Info "  Warning: could not query locks: $_"
    }
}
