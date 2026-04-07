# common.ps1 — Shared utility functions sourced by deploy.ps1, test.ps1, and cleanup.ps1.

function Write-Task {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Blue
}

function Write-Exists {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-Needed {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor DarkGray
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
