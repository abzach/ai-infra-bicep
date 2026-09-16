# test.ps1 — Automated test runner for the enterprise AI Foundry stack.
#
# PARAMETERS
#   -Mode                Static | Validate | Smoke | ChatDual   (required)
#   -EnvironmentSuffix   dev | uat   (required for all modes except Static)
#   -VmAdminPassword     string   (optional; used by Smoke mode when calling deploy.ps1)
#   -ProbePrompt         string   (optional; overrides the probePrompt from config yaml for
#                                  Validate/Smoke modes)

param(
    [Parameter(Mandatory)]
    [ValidateSet('Static', 'Validate', 'Smoke', 'ChatDual')]
    [string] $Mode,

    [ValidateSet('dev','uat')]
    [string] $EnvironmentSuffix,

    [string] $VmAdminPassword,
    [string] $ProbePrompt
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

    throw 'Unable to resolve the script root for test.ps1.'
}

function Test-KeyVaultDirectAccessBlocked {
    param(
        [AllowNull()] [string] $CliOutput
    )

    if ([string]::IsNullOrWhiteSpace($CliOutput)) {
        return $false
    }

    return $CliOutput -match 'ForbiddenByConnection|ForbiddenByFirewall|ForbiddenByRbac|Public network access is disabled|Client address|network access is denied|does not have secrets (get|list) permission|Status: 403|status code 403|invalid status ''Forbidden''' 
}

$scriptRoot = Get-CurrentScriptRoot

if ($Mode -eq 'Static') {
    . (Join-Path $scriptRoot 'common.ps1')

    Initialize-ScriptLogging -ScriptRoot $scriptRoot -ScriptName 'test.ps1 (Static)'
    trap { Write-LogEntry -Level 'ERROR' -Message "Unhandled error: $($_.Exception.Message)"; Write-ScriptTimingSummary -Status 'failed' }

    $env:AZURE_CORE_COLLECT_TELEMETRY = '0'

    $templatePath = Join-Path $scriptRoot '..\bicep\templates\main.bicep'
    if (-not (Test-Path $templatePath)) {
        throw "Required template file not found: $templatePath"
    }

    $modulePath = Join-Path $scriptRoot '..\bicep\modules'
    if (-not (Test-Path $modulePath)) {
        throw "Required Bicep modules directory not found: $modulePath"
    }

    $files  = @((Resolve-Path $templatePath))
    $files += Get-ChildItem -Path $modulePath -Filter '*.bicep' | Select-Object -ExpandProperty FullName

    $passed = $true

    $automationPath = Join-Path $scriptRoot '..\automation'
    $automationFiles = @(Get-ChildItem -Path $automationPath -Filter '*.ps1' -File -ErrorAction Stop | Sort-Object Name)
    if ($automationFiles.Count -eq 0) {
        Write-Needed 'Fail: no top-level Automation runbooks were found'
        $passed = $false
    }
    $runbookNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($automationFile in $automationFiles) {
        $runbookName = [System.IO.Path]::GetFileNameWithoutExtension($automationFile.Name)
        if ($runbookName -notmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or -not $runbookNames.Add($runbookName)) {
            Write-Needed "Fail: invalid or duplicate Automation runbook name '$runbookName'"
            $passed = $false
        }

        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($automationFile.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            Write-Needed "Fail: Automation runbook '$($automationFile.Name)' has parse errors"
            $passed = $false
        } else {
            Write-Exists "Pass: Automation runbook '$($automationFile.Name)' parses successfully"
        }

        $source = Get-Content -LiteralPath $automationFile.FullName -Raw
        if ($source -match 'Add-AzureRmAccount|RunAsConnection|Get-AutomationPSCredential|ClientSecret|ConvertTo-SecureString\s+[''"]') {
            Write-Needed "Fail: Automation runbook '$($automationFile.Name)' contains legacy authentication or embedded credential patterns"
            $passed = $false
        }
    }

    foreach ($templateFile in $files) {
        $fileName = Split-Path $templateFile -Leaf
        Write-Task "Testing: $fileName"

        Write-Task "  [1/2] Building template..."
        try {
            $outFile = Join-Path $env:TEMP "enterprise-$fileName.json"
            az bicep build --file $templateFile --outfile $outFile 2>&1 | Out-Null
            if (Test-Path $outFile) {
                Remove-Item $outFile -Force
                Write-Exists '  Pass: build succeeded'
            } else {
                Write-Needed '  Fail: build output not found'
                $passed = $false
            }
        } catch {
            Write-Needed "  Fail: build error: $_"
            $passed = $false
        }

        Write-Task "  [2/2] Linting template..."
        $lintOutput = az bicep lint --file $templateFile 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Exists '  Pass: no lint errors'
        } else {
            Write-Needed "  Fail: lint errors:`n$lintOutput"
            $passed = $false
        }
    }

    if ($passed) { Write-Exists 'All static tests passed.'; Complete-ScriptLogging -Status 'completed (passed)'; exit 0 }
    else { Write-Needed 'Some static tests failed.'; Complete-ScriptLogging -Status 'completed (failed)'; exit 1 }
}

if (-not $EnvironmentSuffix) {
    Write-Error "-EnvironmentSuffix is required for Mode '$Mode'."
    exit 1
}

. (Join-Path $scriptRoot 'config.ps1')
. (Join-Path $scriptRoot 'common.ps1')

Initialize-ScriptLogging -ScriptRoot $scriptRoot -ScriptName "test.ps1 ($Mode)"
trap { Write-LogEntry -Level 'ERROR' -Message "Unhandled error: $($_.Exception.Message)"; Write-ScriptTimingSummary -Status 'failed' }

$subscriptionId = (az account show --query id --output tsv 2>$null).Trim()
if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
    Write-Error 'Unable to resolve Azure subscription ID from az account show.'
    exit 1
}

$NameSuffix = ($subscriptionId -replace '-', '').Substring(0, 4).ToLower()
$config = Read-EnterpriseEnvironmentConfig -ScriptRoot $scriptRoot -EnvironmentSuffix $EnvironmentSuffix -NameSuffix $NameSuffix

if ($Mode -eq 'Smoke') {
    $Location              = $config.location
    $CoreResourceGroupName = $config.coreResourceGroupName
    $ModelDeploymentName   = $config.modelDeploymentName
    $CapacityK             = [int]$config.capacityK
    $ModelName             = $config.modelName
    $ModelVersion          = $config.modelVersion
    $ModelSkuName          = $config.modelSkuName
    $MlApiVersion          = $config.mlApiVersion
    $OpenaiApiVersion      = $config.openaiApiVersion
    $keyVaultName          = $config.keyVaultName
    $vmName                = $config.vmName
    $openAiAccountName     = $config.openAiAccountName
    $hubName               = $config.hubName
    $projectName           = $config.projectName
    if (-not $ProbePrompt) { $ProbePrompt = $config.probePrompt }

    $deployScript = Join-Path $scriptRoot 'deploy.ps1'

    $deletedAccounts = az cognitiveservices account list-deleted --query "[?name=='$openAiAccountName'].id" -o tsv 2>$null
    if ($deletedAccounts) {
        Write-Needed "Purging soft-deleted OpenAI account '$openAiAccountName'..."
        az cognitiveservices account purge --location $Location --resource-group $CoreResourceGroupName --name $openAiAccountName 2>$null
    }

    $armToken   = (az account get-access-token --query accessToken -o tsv 2>$null)
    $armHeaders = @{ Authorization = "Bearer $armToken" }
    $sub        = (az account show --query id -o tsv 2>$null)
    foreach ($wsName in @($hubName, $projectName)) {
        $wsUrl = "https://management.azure.com/subscriptions/$sub/resourceGroups/$CoreResourceGroupName/providers/Microsoft.MachineLearningServices/workspaces/$wsName`?api-version=$MlApiVersion&forcePurge=true"
        try {
            Invoke-RestMethod -Method DELETE -Uri $wsUrl -Headers $armHeaders -ErrorAction Stop | Out-Null
            Write-Exists "Purged stale ML workspace '$wsName'."
        } catch {
            if ($_.Exception.Response.StatusCode -ne 'NotFound') {
                Write-Info "Warning: could not purge workspace '$wsName': $($_.Exception.Message)"
            }
        }
    }

    Write-Task 'Step 1/3: Deploying infrastructure...'
    $deployArgs = @{ EnvironmentSuffix = $EnvironmentSuffix }
    if ($VmAdminPassword) { $deployArgs['VmAdminPassword'] = $VmAdminPassword }
    & $deployScript @deployArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Needed 'Smoke test failed during deployment.'
        exit 1
    }

    Write-Task "Waiting for OpenAI account '$openAiAccountName' to be ready..."
    $maxWait = 30
    for ($i = 1; $i -le $maxWait; $i++) {
        $oaiState = az cognitiveservices account show --resource-group $CoreResourceGroupName --name $openAiAccountName --query "properties.provisioningState" -o tsv 2>$null
        if ($oaiState -eq 'Succeeded') {
            Write-Exists "OpenAI account is ready."
            break
        }
        Write-Info "  State: $oaiState ($i/$maxWait). Retrying in 20s..."
        Start-Sleep -Seconds 20
        if ($i -eq $maxWait) {
            Write-Needed "Timed out waiting for OpenAI account to reach Succeeded state."
            exit 1
        }
    }

    Write-Task "Creating model deployment '$ModelDeploymentName' on '$openAiAccountName'..."
    az cognitiveservices account deployment create `
        --resource-group $CoreResourceGroupName `
        --name $openAiAccountName `
        --deployment-name $ModelDeploymentName `
        --model-name $ModelName `
        --model-version $ModelVersion `
        --model-format OpenAI `
        --sku-capacity $CapacityK `
        --sku-name $ModelSkuName

    if ($LASTEXITCODE -ne 0) {
        Write-Needed 'Smoke test failed: model deployment creation failed.'
        exit 1
    }

    Write-Task 'Step 2/3: Validating deployed resources...'
}

if ($Mode -eq 'Validate' -or $Mode -eq 'Smoke') {
    $CoreResourceGroupName    = $config.coreResourceGroupName
    $NetworkResourceGroupName = $config.networkResourceGroupName
    $storageAccountName       = $config.storageAccountName
    $keyVaultName             = $config.keyVaultName
    $openAiAccountName        = $config.openAiAccountName
    $hubName                  = $config.hubName
    $projectName              = $config.projectName
    $hubManagedIdentityName   = $config.hubManagedIdentityName
    $vmManagedIdentityName    = $config.vmManagedIdentityName
    $automationManagedIdentityName = $config.automationManagedIdentityName
    $automationAccountName    = $config.automationAccountName
    $legacyManagedIdentityName = $config.legacyManagedIdentityName
    $vnetName                 = $config.vnetName
    $vmName                   = $config.vmName

    # Component deployment flags decide which resources must exist; disabled components must be absent.
    $deployStorageFlag      = $config.deployStorage -eq 'true'
    $deployLogAnalyticsFlag = $config.deployLogAnalytics -eq 'true'
    $deployAiFoundryFlag    = $config.deployAiFoundry -eq 'true'
    $deployVmFlag           = $config.deployVm -eq 'true'

    $passed = $true

    Write-Task 'Testing enterprise resources...'
    Write-Info "  Core RG    : $CoreResourceGroupName"
    Write-Info "  Network RG : $NetworkResourceGroupName"

    $storage = az storage account show --name $storageAccountName --resource-group $CoreResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $deployStorageFlag) {
        if ($storage) { Write-Needed "Fail: deployStorage=false but storage account '$storageAccountName' still exists"; $passed = $false }
        else { Write-Info 'Skip: deployStorage=false; storage account checks skipped.' }
    } elseif (-not $storage) {
        Write-Needed "Fail: storage account '$storageAccountName' not found"
        $passed = $false
    } else {
        $httpsOnly = if ($null -ne $storage.enableHttpsTrafficOnly) { $storage.enableHttpsTrafficOnly } else { $storage.properties.supportsHttpsTrafficOnly }
        if ($httpsOnly -eq $true) { Write-Exists 'Pass: HTTPS-only enabled on storage' }
        else { Write-Needed 'Fail: HTTPS-only not enabled on storage'; $passed = $false }
        if ($storage.sku.name -eq $config.skuName) { Write-Exists "Pass: storage redundancy is '$($config.skuName)'" }
        else { Write-Needed "Fail: storage redundancy is '$($storage.sku.name)', expected '$($config.skuName)'"; $passed = $false }
        if ($storage.accessTier -eq $config.storageAccessTier) { Write-Exists "Pass: storage access tier is '$($config.storageAccessTier)'" }
        else { Write-Needed "Fail: storage access tier is '$($storage.accessTier)', expected '$($config.storageAccessTier)'"; $passed = $false }

        $blobProperties = az storage account blob-service-properties show --account-name $storageAccountName --resource-group $CoreResourceGroupName --output json 2>$null | ConvertFrom-Json
        if (-not $blobProperties) {
            Write-Needed 'Fail: storage blob service properties could not be read'; $passed = $false
        } else {
            $actualBlobRetention = if ($blobProperties.deleteRetentionPolicy.enabled) { [int]$blobProperties.deleteRetentionPolicy.days } else { 0 }
            $actualContainerRetention = if ($blobProperties.containerDeleteRetentionPolicy.enabled) { [int]$blobProperties.containerDeleteRetentionPolicy.days } else { 0 }
            if ($actualBlobRetention -eq [int]$config.storageBlobSoftDeleteRetentionDays) { Write-Exists "Pass: blob soft-delete retention is $actualBlobRetention days" }
            else { Write-Needed "Fail: blob soft-delete retention is $actualBlobRetention, expected $($config.storageBlobSoftDeleteRetentionDays)"; $passed = $false }
            if ($actualContainerRetention -eq [int]$config.storageContainerSoftDeleteRetentionDays) { Write-Exists "Pass: container soft-delete retention is $actualContainerRetention days" }
            else { Write-Needed "Fail: container soft-delete retention is $actualContainerRetention, expected $($config.storageContainerSoftDeleteRetentionDays)"; $passed = $false }
        }
    }

    $vault = az keyvault show --name $keyVaultName --resource-group $CoreResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $vault) {
        Write-Needed "Fail: Key Vault '$keyVaultName' not found"
        $passed = $false
    } else {
        if ([int]$vault.properties.softDeleteRetentionInDays -eq [int]$config.keyVaultSoftDeleteRetentionDays) {
            Write-Exists "Pass: Key Vault soft-delete retention is $($config.keyVaultSoftDeleteRetentionDays) days"
        } else {
            Write-Needed "Fail: Key Vault soft-delete retention is '$($vault.properties.softDeleteRetentionInDays)', expected '$($config.keyVaultSoftDeleteRetentionDays)'"; $passed = $false
        }
        $secretNames            = @('openai-endpoint','openai-deployment')
        $canReadSecretsDirectly = $true

        foreach ($secretName in $secretNames) {
            $secretRaw = az keyvault secret show --vault-name $keyVaultName --name $secretName --output json 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Exists "Pass: secret '$secretName' exists"
                continue
            }
            if (Test-KeyVaultDirectAccessBlocked -CliOutput $secretRaw) {
                $canReadSecretsDirectly = $false
                break
            }
            Write-Needed "Fail: secret '$secretName' missing"
            $passed = $false
        }

        if (-not $canReadSecretsDirectly) {
            Write-Info 'Skip: Key Vault data-plane not accessible from this host; secret existence check skipped (run from inside the VNet to validate secrets directly).'
        }
    }

    $openAi = az cognitiveservices account show --name $openAiAccountName --resource-group $CoreResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $openAi) {
        Write-Needed "Fail: Azure OpenAI account '$openAiAccountName' not found"
        $passed = $false
    } else {
        if ($openAi.kind -eq 'OpenAI') { Write-Exists 'Pass: OpenAI kind validated' }
        else { Write-Needed "Fail: OpenAI kind mismatch: $($openAi.kind)"; $passed = $false }
        if ($openAi.properties.disableLocalAuth -eq $true) { Write-Exists 'Pass: OpenAI local authentication is disabled' }
        else { Write-Needed 'Fail: OpenAI local authentication must remain disabled'; $passed = $false }
    }

    $hub = az resource show --name $hubName --resource-group $CoreResourceGroupName --resource-type Microsoft.MachineLearningServices/workspaces --output json 2>$null | ConvertFrom-Json
    $project = az resource show --name $projectName --resource-group $CoreResourceGroupName --resource-type Microsoft.MachineLearningServices/workspaces --output json 2>$null | ConvertFrom-Json
    if (-not $deployAiFoundryFlag) {
        if ($hub -or $project) { Write-Needed 'Fail: deployAiFoundry=false but the AI Hub or AI Project still exists'; $passed = $false }
        else { Write-Info 'Skip: deployAiFoundry=false; AI Hub and AI Project checks skipped.' }
    } else {
        if (-not $hub) { Write-Needed "Fail: AI Hub '$hubName' not found"; $passed = $false }
        else { Write-Exists "Pass: AI Hub '$hubName' exists" }

        if (-not $project) { Write-Needed "Fail: AI Project '$projectName' not found"; $passed = $false }
        else { Write-Exists "Pass: AI Project '$projectName' exists" }
    }

    $hubManagedIdentity = az identity show --name $hubManagedIdentityName --resource-group $CoreResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $hubManagedIdentity) { Write-Needed "Fail: AI Hub managed identity '$hubManagedIdentityName' not found"; $passed = $false }
    else { Write-Exists "Pass: AI Hub managed identity '$hubManagedIdentityName' exists" }

    $vmManagedIdentity = az identity show --name $vmManagedIdentityName --resource-group $CoreResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $vmManagedIdentity) { Write-Needed "Fail: VM managed identity '$vmManagedIdentityName' not found"; $passed = $false }
    else { Write-Exists "Pass: VM managed identity '$vmManagedIdentityName' exists" }

    if ($config.deployAutomation -eq 'true') {
        $automationManagedIdentity = az identity show --name $automationManagedIdentityName --resource-group $CoreResourceGroupName --output json 2>$null | ConvertFrom-Json
        if (-not $automationManagedIdentity) {
            Write-Needed "Fail: Automation managed identity '$automationManagedIdentityName' not found"; $passed = $false
        } else {
            Write-Exists "Pass: Automation managed identity '$automationManagedIdentityName' exists"
        }

        $automationAccountResourceUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$CoreResourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName"
        $automationAccountUri = "$automationAccountResourceUri`?api-version=2024-10-23"
        $automationAccount = az rest --method get --url $automationAccountUri --output json 2>$null | ConvertFrom-Json
        if (-not $automationAccount) {
            Write-Needed "Fail: Automation Account '$automationAccountName' not found"; $passed = $false
        } elseif ($automationAccount.identity.type -ne 'UserAssigned') {
            Write-Needed "Fail: Automation Account '$automationAccountName' is not using only a user-assigned identity"; $passed = $false
        } else {
            Write-Exists "Pass: Automation Account '$automationAccountName' uses a user-assigned identity"
        }

        $automationPath = Join-Path $scriptRoot '..\automation'
        foreach ($automationFile in @(Get-ChildItem -Path $automationPath -Filter '*.ps1' -File)) {
            $runbookName = [System.IO.Path]::GetFileNameWithoutExtension($automationFile.Name)
            $runbookUri = "$automationAccountResourceUri/runbooks/$runbookName`?api-version=2024-10-23"
            $runbook = az rest --method get --url $runbookUri --output json 2>$null | ConvertFrom-Json
            if (-not $runbook -or $runbook.properties.state -ne 'Published') {
                Write-Needed "Fail: Automation runbook '$runbookName' is not published"; $passed = $false
            } else {
                Write-Exists "Pass: Automation runbook '$runbookName' is published"
            }
        }

        if ($config.vmStartScheduleEnabled -eq 'true') {
            $scheduleUri = "$automationAccountResourceUri/schedules/$($config.vmStartScheduleName)`?api-version=2024-10-23"
            $schedule = az rest --method get --url $scheduleUri --output json 2>$null | ConvertFrom-Json
            if (-not $schedule -or $schedule.properties.frequency -ne 'Day' -or $schedule.properties.timeZone -ne $config.vmStartScheduleTimeZone) {
                Write-Needed "Fail: daily VM start schedule '$($config.vmStartScheduleName)' is missing or incorrect"; $passed = $false
            } else {
                Write-Exists "Pass: daily VM start schedule '$($config.vmStartScheduleName)' exists"
            }
        }
    }

    $legacyManagedIdentity = az identity show --name $legacyManagedIdentityName --resource-group $CoreResourceGroupName --output json 2>$null | ConvertFrom-Json
    if ($legacyManagedIdentity) { Write-Needed "Fail: retired shared managed identity '$legacyManagedIdentityName' still exists"; $passed = $false }
    else { Write-Exists 'Pass: retired shared managed identity is absent' }

    $vnet = az network vnet show --name $vnetName --resource-group $NetworkResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $vnet) { Write-Needed "Fail: virtual network '$vnetName' not found in '$NetworkResourceGroupName'"; $passed = $false }
    else {
        if ($config.vnetAddressSpace -in $vnet.addressSpace.addressPrefixes) { Write-Exists "Pass: VNet address space includes '$($config.vnetAddressSpace)'" }
        else { Write-Needed "Fail: VNet address spaces '$($vnet.addressSpace.addressPrefixes -join ', ')' do not include '$($config.vnetAddressSpace)'"; $passed = $false }
        $servicesSubnet = $vnet.subnets | Where-Object name -eq 'services'
        $vmSubnet = $vnet.subnets | Where-Object name -eq 'vm'
        if ($servicesSubnet.addressPrefix -eq $config.servicesSubnetAddressPrefix) { Write-Exists "Pass: services subnet is '$($config.servicesSubnetAddressPrefix)'" }
        else { Write-Needed "Fail: services subnet is '$($servicesSubnet.addressPrefix)', expected '$($config.servicesSubnetAddressPrefix)'"; $passed = $false }
        if ($vmSubnet.addressPrefix -eq $config.vmSubnetAddressPrefix) { Write-Exists "Pass: VM subnet is '$($config.vmSubnetAddressPrefix)'" }
        else { Write-Needed "Fail: VM subnet is '$($vmSubnet.addressPrefix)', expected '$($config.vmSubnetAddressPrefix)'"; $passed = $false }
    }

    $vmNicName = "$vmName-nic"
    $vmNic = az network nic show --name $vmNicName --resource-group $NetworkResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $vmNic) {
        Write-Needed "Fail: VM NIC '$vmNicName' not found"; $passed = $false
    } else {
        $expectedAcceleratedNetworking = $config.vmAcceleratedNetworking -eq 'true'
        if ($vmNic.enableAcceleratedNetworking -eq $expectedAcceleratedNetworking) { Write-Exists "Pass: accelerated networking is '$expectedAcceleratedNetworking'" }
        else { Write-Needed "Fail: accelerated networking is '$($vmNic.enableAcceleratedNetworking)', expected '$expectedAcceleratedNetworking'"; $passed = $false }
    }

    $privateEndpoints = az network private-endpoint list --resource-group $NetworkResourceGroupName --query "[].name" --output tsv 2>$null
    if (($privateEndpoints | Measure-Object).Count -lt 3) {
        Write-Needed 'Fail: expected at least 3 private endpoints'; $passed = $false
    } else {
        Write-Exists 'Pass: private endpoints found for dependent services'
    }

    $vm = az vm show --name $vmName --resource-group $CoreResourceGroupName --show-details --output json 2>$null | ConvertFrom-Json
    if (-not $deployVmFlag) {
        if ($vm) { Write-Needed "Fail: deployVm=false but jumpbox VM '$vmName' still exists"; $passed = $false }
        else { Write-Info 'Skip: deployVm=false; jumpbox VM checks skipped.' }
    } elseif (-not $vm) {
        Write-Needed "Fail: jumpbox VM '$vmName' not found"; $passed = $false
    } else {
        $expectedImage = "$($config.vmImagePublisher):$($config.vmImageOffer):$($config.vmImageSku):$($config.vmImageVersion)"
        $actualImage = "$($vm.storageProfile.imageReference.publisher):$($vm.storageProfile.imageReference.offer):$($vm.storageProfile.imageReference.sku):$($vm.storageProfile.imageReference.version)"
        if ($actualImage -ieq $expectedImage) {
            Write-Exists "Pass: jumpbox VM uses configured image '$expectedImage'"
        } else {
            Write-Needed "Fail: VM image is '$actualImage', expected '$expectedImage'"; $passed = $false
        }
        if ($vm.hardwareProfile.vmSize -eq $config.vmSize) {
            Write-Exists "Pass: jumpbox VM size is '$($config.vmSize)'"
        } else {
            Write-Needed "Fail: VM size is '$($vm.hardwareProfile.vmSize)', expected '$($config.vmSize)'"; $passed = $false
        }
        if ($vm.storageProfile.osDisk.managedDisk.storageAccountType -eq $config.vmOsDiskStorageAccountType) {
            Write-Exists "Pass: VM OS disk tier is '$($config.vmOsDiskStorageAccountType)'"
        } else {
            Write-Needed "Fail: VM OS disk tier is '$($vm.storageProfile.osDisk.managedDisk.storageAccountType)', expected '$($config.vmOsDiskStorageAccountType)'"; $passed = $false
        }
    }

    # ---- A1: Auto-shutdown schedule ----
    $autoShutdownEnabled = $config.vmAutoShutdownEnabled -eq 'true'
    if (-not $autoShutdownEnabled) {
        Write-Info 'Skip: vmAutoShutdownEnabled=false; auto-shutdown schedule check skipped.'
    } else {
        $autoShutdownScheduleName = "shutdown-computevm-$vmName"
        $shutdownRaw = az resource show `
            --resource-group $CoreResourceGroupName `
            --resource-type 'Microsoft.DevTestLab/schedules' `
            --name $autoShutdownScheduleName `
            --output json 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($shutdownRaw)) {
            Write-Needed "Fail: auto-shutdown schedule '$autoShutdownScheduleName' not found"; $passed = $false
        } else {
            $shutdown = $shutdownRaw | ConvertFrom-Json
            $shutdownOk = $true
            if ($shutdown.properties.status -ne 'Enabled') {
                Write-Needed "Fail: auto-shutdown status is '$($shutdown.properties.status)', expected Enabled"; $passed = $false; $shutdownOk = $false
            }
            if ($shutdown.properties.dailyRecurrence.time -ne $config.vmAutoShutdownTime) {
                Write-Needed "Fail: auto-shutdown time is '$($shutdown.properties.dailyRecurrence.time)', expected '$($config.vmAutoShutdownTime)'"; $passed = $false; $shutdownOk = $false
            }
            if ($shutdown.properties.timeZoneId -ne $config.vmAutoShutdownTimeZone) {
                Write-Needed "Fail: auto-shutdown timezone is '$($shutdown.properties.timeZoneId)', expected '$($config.vmAutoShutdownTimeZone)'"; $passed = $false; $shutdownOk = $false
            }
            if ($shutdownOk) {
                Write-Exists "Pass: auto-shutdown enabled at $($config.vmAutoShutdownTime) ($($config.vmAutoShutdownTimeZone))"
            }
        }
    }

    # ---- A2: VM Spot configuration ----
    if ($vm) {
        $vmPriority = ''
        if ($vm.PSObject.Properties['priority']) {
            $vmPriority = [string]$vm.priority
        }

        $vmEvictionPolicy = ''
        if ($vm.PSObject.Properties['evictionPolicy']) {
            $vmEvictionPolicy = [string]$vm.evictionPolicy
        }

        $vmUseSpot = $config.vmUseSpot -eq 'true'
        if ($vmUseSpot) {
            if ($vmPriority -eq 'Spot' -and $vmEvictionPolicy -eq 'Deallocate') {
                Write-Exists 'Pass: VM is Spot with Deallocate eviction policy'
            } else {
                Write-Needed "Fail: expected Spot/Deallocate but got priority='$vmPriority' evictionPolicy='$vmEvictionPolicy'"; $passed = $false
            }
        } else {
            if ([string]::IsNullOrWhiteSpace($vmPriority) -or $vmPriority -eq 'Regular') {
                Write-Exists 'Pass: VM priority is Regular (on-demand)'
            } else {
                Write-Needed "Fail: expected Regular priority but VM has priority='$vmPriority'"; $passed = $false
            }
        }
    }

    # ---- B1: VM extensions provisioned ----
    $expectedExtensions = @('AzureMonitorWindowsAgent', 'IaaSAntimalware', 'AzureDiskEncryption')
    $extensionsRaw = az vm extension list --vm-name $vmName --resource-group $CoreResourceGroupName --output json 2>$null
    if ([string]::IsNullOrWhiteSpace($extensionsRaw)) {
        Write-Needed 'Fail: could not retrieve VM extension list'; $passed = $false
    } else {
        $extensions = $extensionsRaw | ConvertFrom-Json
        $extensionsFailed = $false
        foreach ($extName in $expectedExtensions) {
            $ext = $extensions | Where-Object { $_.name -eq $extName }
            if (-not $ext) {
                Write-Needed "Fail: VM extension '$extName' not found"; $passed = $false; $extensionsFailed = $true
            } elseif ($ext.provisioningState -ne 'Succeeded') {
                Write-Needed "Fail: VM extension '$extName' provisioningState is '$($ext.provisioningState)'"; $passed = $false; $extensionsFailed = $true
            }
        }
        if (-not $extensionsFailed) {
            Write-Exists 'Pass: VM extensions all provisioned (AMA, Antimalware, ADE)'
        }
    }

    # ---- B2: Chat launcher artifacts use supported shell path ----
    $launcherValidationScript = @'
$ErrorActionPreference = 'Stop'

$appDir = 'C:\ChatApp'
$launcherPath = Join-Path $appDir 'launch-chat.bat'
$expectedPowerShellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$expectedPowerShellPattern = '(?im)(%SystemRoot%|[A-Za-z]:\\Windows)\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'AI Chat.lnk'

if (-not (Test-Path $launcherPath)) {
    throw "launch-chat.bat not found at $launcherPath"
}

$launcherContent = Get-Content -Path $launcherPath -Raw
if ($launcherContent -match '(?im)\bpwsh(\.exe)?\b') {
    throw 'launch-chat.bat still references pwsh.'
}

if ($launcherContent -notmatch $expectedPowerShellPattern) {
    throw "launch-chat.bat does not reference the expected Windows PowerShell command path. Expected '$expectedPowerShellPath' or the equivalent %SystemRoot% form."
}

if (-not (Test-Path $shortcutPath)) {
    throw "Desktop shortcut not found at $shortcutPath"
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
if ($shortcut.TargetPath -ne $launcherPath) {
    throw "Desktop shortcut target is '$($shortcut.TargetPath)' instead of '$launcherPath'."
}

if (-not [string]::IsNullOrWhiteSpace($shortcut.Arguments)) {
    throw "Desktop shortcut arguments should be empty when targeting launch-chat.bat, found '$($shortcut.Arguments)'."
}

Write-Host 'LAUNCHER_VALIDATION_OK'
'@

    $launcherValidationFile = [System.IO.Path]::GetTempFileName() + '.ps1'
    Set-Content -Path $launcherValidationFile -Value $launcherValidationScript -Encoding UTF8

    $launcherValidationResult = az vm run-command invoke `
        --resource-group $CoreResourceGroupName `
        --name $vmName `
        --command-id RunPowerShellScript `
        --scripts "@$launcherValidationFile" `
        --output json

    Remove-Item $launcherValidationFile -Force -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($launcherValidationResult)) {
        Write-Needed 'Fail: could not validate VM chat launcher artifacts'; $passed = $false
    } else {
        $launcherValidationOutput = $launcherValidationResult | ConvertFrom-Json
        $launcherValidationMessage = if ($launcherValidationOutput.value) {
            ($launcherValidationOutput.value | ForEach-Object { $_.message }) -join "`n"
        } else {
            [string]$launcherValidationResult
        }

        if ($launcherValidationMessage -match 'LAUNCHER_VALIDATION_OK') {
            Write-Exists 'Pass: VM chat launcher uses Windows PowerShell and shortcut targets launch-chat.bat'
        } else {
            Write-Needed "Fail: VM chat launcher validation failed:`n$launcherValidationMessage"; $passed = $false
        }
    }

    # ---- C1: NSG has deny-all RDP rule ----
    $nsgResourceName = "${vmName}-nsg"
    $nsg = az network nsg show --name $nsgResourceName --resource-group $NetworkResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $nsg) {
        Write-Needed "Fail: NSG '$nsgResourceName' not found in '$NetworkResourceGroupName'"; $passed = $false
    } else {
        $denyRdpRule = $nsg.securityRules | Where-Object {
            $_.access -eq 'Deny' -and
            $_.direction -eq 'Inbound' -and
            ($_.destinationPortRange -eq '3389' -or $_.destinationPortRanges -contains '3389')
        }
        if ($denyRdpRule) {
            Write-Exists "Pass: NSG '$nsgResourceName' has deny-all RDP rule"
        } else {
            Write-Needed "Fail: NSG '$nsgResourceName' missing inbound Deny rule for port 3389"; $passed = $false
        }
    }

    # ---- C2: Private DNS zones present ----
    $expectedDnsZones = @(
        'privatelink.vaultcore.azure.net',
        'privatelink.openai.azure.com',
        'privatelink.blob.core.windows.net',
        'privatelink.api.azureml.ms'
    )
    $dnsZoneList = az network private-dns zone list --resource-group $NetworkResourceGroupName --query '[].name' --output tsv 2>$null
    $dnsZonesMissing = $false
    foreach ($zone in $expectedDnsZones) {
        if ($dnsZoneList -notcontains $zone) {
            Write-Needed "Fail: private DNS zone '$zone' not found in '$NetworkResourceGroupName'"; $passed = $false; $dnsZonesMissing = $true
        }
    }
    if (-not $dnsZonesMissing) {
        Write-Exists 'Pass: all expected private DNS zones present'
    }

    # ---- D1: Key Vault security settings ----
    if ($vault) {
        $kvOk = $true
        if ($vault.properties.enabledForDiskEncryption -ne $true) {
            Write-Needed 'Fail: Key Vault enabledForDiskEncryption is not true'; $passed = $false; $kvOk = $false
        }
        if ($vault.properties.networkAcls.defaultAction -ne 'Deny') {
            Write-Needed "Fail: Key Vault networkAcls.defaultAction is '$($vault.properties.networkAcls.defaultAction)', expected Deny"; $passed = $false; $kvOk = $false
        }
        if ($vault.properties.publicNetworkAccess -ne 'Disabled') {
            Write-Needed "Fail: Key Vault publicNetworkAccess is '$($vault.properties.publicNetworkAccess)', expected Disabled"; $passed = $false; $kvOk = $false
        }
        if ($kvOk) {
            Write-Exists 'Pass: Key Vault is private-only with disk-encryption support and a default-deny ACL'
        }
    }

    # ---- D2: OpenAI public access disabled ----
    if ($openAi) {
        $oaiPublicAccess = if ($openAi.properties) { $openAi.properties.publicNetworkAccess } else { $openAi.publicNetworkAccess }
        if ($oaiPublicAccess -eq 'Disabled') {
            Write-Exists 'Pass: OpenAI public network access is Disabled'
        } else {
            Write-Needed "Fail: OpenAI publicNetworkAccess is '$oaiPublicAccess', expected Disabled"; $passed = $false
        }
    }

    # ---- D3: AI Hub and Project public access disabled ----
    if ($hub) {
        if ($hub.properties.publicNetworkAccess -eq 'Disabled') {
            Write-Exists "Pass: AI Hub '$hubName' public network access is Disabled"
        } else {
            Write-Needed "Fail: AI Hub '$hubName' publicNetworkAccess is '$($hub.properties.publicNetworkAccess)', expected Disabled"; $passed = $false
        }
    }
    if ($project) {
        if ($project.properties.publicNetworkAccess -eq 'Disabled') {
            Write-Exists "Pass: AI Project '$projectName' public network access is Disabled"
        } else {
            Write-Needed "Fail: AI Project '$projectName' publicNetworkAccess is '$($project.properties.publicNetworkAccess)', expected Disabled"; $passed = $false
        }
    }

    # ---- D4: Storage security settings ----
    if ($storage) {
        $storageSecOk = $true
        $storageNetAcls = if ($storage.networkRuleSet) { $storage.networkRuleSet } else { $storage.networkAcls }
        if ($storageNetAcls.defaultAction -ne 'Deny') {
            Write-Needed "Fail: storage networkAcls.defaultAction is '$($storageNetAcls.defaultAction)', expected Deny"; $passed = $false; $storageSecOk = $false
        }
        if ($storage.publicNetworkAccess -ne 'Disabled') {
            Write-Needed "Fail: storage publicNetworkAccess is '$($storage.publicNetworkAccess)', expected Disabled"; $passed = $false; $storageSecOk = $false
        }
        $tlsVersion = $storage.minimumTlsVersion
        if ($tlsVersion -notin @('TLS1_2', 'TLS1_3')) {
            Write-Needed "Fail: storage minimumTlsVersion is '$tlsVersion', expected TLS1_2 or TLS1_3"; $passed = $false; $storageSecOk = $false
        }
        if ($storageSecOk) {
            Write-Exists "Pass: storage is private-only with a default-deny ACL and minimum TLS $tlsVersion"
        }
    }

    # ---- E1: Log Analytics workspace ----
    $lawWorkspaceName = $config.lawWorkspaceName
    $law = az monitor log-analytics workspace show --workspace-name $lawWorkspaceName --resource-group $CoreResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $deployLogAnalyticsFlag) {
        if ($law) { Write-Needed "Fail: deployLogAnalytics=false but workspace '$lawWorkspaceName' still exists"; $passed = $false }
        else { Write-Info 'Skip: deployLogAnalytics=false; Log Analytics checks skipped.' }
    } elseif (-not $law) {
        Write-Needed "Fail: Log Analytics workspace '$lawWorkspaceName' not found"; $passed = $false
    } else {
        $expectedRetention = [int]$config.logAnalyticsRetentionDays
        $actualRetention   = [int]$law.retentionInDays
        if ($actualRetention -ge $expectedRetention) {
            Write-Exists "Pass: Log Analytics workspace '$lawWorkspaceName' exists (retention: ${actualRetention}d)"
        } else {
            Write-Needed "Fail: Log Analytics retention is ${actualRetention}d, expected >= ${expectedRetention}d"; $passed = $false
        }
    }

    # ---- E2: Diagnostic settings on OpenAI and AI Hub ----
    $auditDiagnosticsEnabled = $config.enableAuditDiagnostics -eq 'true'
    if (-not $auditDiagnosticsEnabled) {
        Write-Info 'Skip: enableAuditDiagnostics=false; diagnostic settings check skipped.'
    } else {
        if ($openAi) {
            $oaiDiag = az monitor diagnostic-settings list --resource $openAi.id --output json 2>$null | ConvertFrom-Json
            $oaiDiagCount = if ($null -eq $oaiDiag) { 0 } elseif ($oaiDiag -is [System.Array]) { $oaiDiag.Count } elseif ($oaiDiag.PSObject.Properties['value']) { @($oaiDiag.value).Count } else { 1 }
            if ($oaiDiagCount -ge 1) {
                Write-Exists 'Pass: diagnostic settings configured on OpenAI'
            } else {
                Write-Needed 'Fail: no diagnostic settings found on OpenAI'; $passed = $false
            }
        }
        if ($hub) {
            $hubDiag = az monitor diagnostic-settings list --resource $hub.id --output json 2>$null | ConvertFrom-Json
            $hubDiagCount = if ($null -eq $hubDiag) { 0 } elseif ($hubDiag -is [System.Array]) { $hubDiag.Count } elseif ($hubDiag.PSObject.Properties['value']) { @($hubDiag.value).Count } else { 1 }
            if ($hubDiagCount -ge 1) {
                Write-Exists "Pass: diagnostic settings configured on AI Hub '$hubName'"
            } else {
                Write-Needed "Fail: no diagnostic settings found on AI Hub '$hubName'"; $passed = $false
            }
        }
    }

    # ---- F1: Workload-specific managed identity role assignments ----
    $identityRoleRequirements = @(
        [pscustomobject]@{ Identity = $hubManagedIdentity; Name = 'AI Hub managed identity'; Roles = @(
            [pscustomobject]@{ Id = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'; Name = 'Storage Blob Data Contributor' },
            [pscustomobject]@{ Id = '4633458b-17de-408a-b874-0445c86b69e6'; Name = 'Key Vault Secrets User' },
            [pscustomobject]@{ Id = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'; Name = 'Cognitive Services OpenAI User' }
        ) },
        [pscustomobject]@{ Identity = $vmManagedIdentity; Name = 'VM managed identity'; Roles = @(
            [pscustomobject]@{ Id = '4633458b-17de-408a-b874-0445c86b69e6'; Name = 'Key Vault Secrets User' },
            [pscustomobject]@{ Id = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'; Name = 'Cognitive Services OpenAI User' }
        ) }
    )
    foreach ($identityRoleRequirement in $identityRoleRequirements) {
        if (-not $identityRoleRequirement.Identity) {
            continue
        }
        $assignments = az role assignment list --assignee $identityRoleRequirement.Identity.principalId --all --output json 2>$null | ConvertFrom-Json
        $rbacFailed = $false
        foreach ($role in $identityRoleRequirement.Roles) {
            $found = $assignments | Where-Object { $_.roleDefinitionId -like "*$($role.Id)" }
            if (-not $found) {
                Write-Needed "Fail: $($identityRoleRequirement.Name) missing role '$($role.Name)' ($($role.Id))"; $passed = $false; $rbacFailed = $true
            }
        }
        if (-not $rbacFailed) {
            Write-Exists "Pass: $($identityRoleRequirement.Name) has all required roles"
        }
    }

    # ---- G1: Mandatory tags on core resources ----
    if ($config.tagWorkload -and $config.tagManagedBy) {
        $mandatoryTags = @{
            environment = $config.tagEnvironment
            project     = $config.tagProject
            workload    = $config.tagWorkload
            managedBy   = $config.tagManagedBy
        }
        $taggedResources = @(
            [pscustomobject]@{ Name = 'storage';  Tags = $storage.tags },
            [pscustomobject]@{ Name = 'Key Vault'; Tags = $vault.tags },
            [pscustomobject]@{ Name = 'OpenAI';   Tags = $openAi.tags },
            [pscustomobject]@{ Name = 'VM';       Tags = $vm.tags }
        )
        $tagsFailed = $false
        foreach ($res in $taggedResources) {
            if (-not $res.Tags) { continue }
            foreach ($key in $mandatoryTags.Keys) {
                $expected = $mandatoryTags[$key]
                $actual   = $res.Tags.$key
                if ($actual -ne $expected) {
                    Write-Needed "Fail: $($res.Name) tag '$key' is '$actual', expected '$expected'"; $passed = $false; $tagsFailed = $true
                }
            }
        }
        if (-not $tagsFailed) {
            Write-Exists 'Pass: mandatory tags present on core resources'
        }
    }

    if ($Mode -eq 'Validate') {
        if ($passed) { Write-Exists 'All tests passed.'; exit 0 }
        # Exit 1 so the pipeline stage shows as failed when checks do not pass.
        # continueOnError: true in deploy-dev.yml keeps the pipeline non-blocking while
        # still surfacing the failure signal until a VNet-connected agent is available.
        else { Write-Needed 'Some tests failed.'; exit 1 }
    }

    if (-not $passed) {
        Write-Needed 'Smoke test failed during resource validation.'
        exit 1
    }
}

if ($Mode -eq 'Smoke') {
    Write-Task 'Step 3/3: Probing model endpoint from inside the VM...'

    $smokeMiClientId = (az identity show --name $config.vmManagedIdentityName --resource-group $CoreResourceGroupName --query clientId --output tsv 2>$null).Trim()

    $smokeScript = @'

$ErrorActionPreference = 'Stop'

$keyVaultToken = (Invoke-RestMethod -Headers @{ Metadata = 'true' } -Method GET -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net&client_id=__MI_CLIENT_ID__').access_token
$kvHeaders = @{ Authorization = "Bearer $keyVaultToken" }
$endpointSecret   = Invoke-RestMethod -Uri 'https://__KEYVAULT_NAME__.vault.azure.net/secrets/openai-endpoint?api-version=7.4'   -Headers $kvHeaders -Method GET
$deploymentSecret = Invoke-RestMethod -Uri 'https://__KEYVAULT_NAME__.vault.azure.net/secrets/openai-deployment?api-version=7.4' -Headers $kvHeaders -Method GET

$openAiToken = (Invoke-RestMethod -Headers @{ Metadata = 'true' } -Method GET -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://cognitiveservices.azure.com/&client_id=__MI_CLIENT_ID__').access_token
$openAiHeaders = @{ Authorization = "Bearer $openAiToken"; 'Content-Type' = 'application/json' }
$body = @{
    messages = @(
        @{ role = 'system'; content = 'You are a concise assistant.' },
        @{ role = 'user'; content = '__PROBE_PROMPT__' }
    )
    temperature = 0
    max_tokens  = 32
} | ConvertTo-Json -Depth 5

$endpoint   = $endpointSecret.value.TrimEnd('/')
$deployment = $deploymentSecret.value
$response   = Invoke-RestMethod -Uri "$endpoint/openai/deployments/$deployment/chat/completions?api-version=__OPENAI_API_VERSION__" -Headers $openAiHeaders -Method POST -Body $body

if (-not $response.choices[0].message.content) { throw 'Model response was empty.' }

Write-Host $response.choices[0].message.content
'@

    $safeProbePrompt = $ProbePrompt -replace "'", "''"
    $safeProbePrompt = $safeProbePrompt -replace '\$', '$$'
    $smokeScript = $smokeScript -replace '__KEYVAULT_NAME__',      $keyVaultName
    $smokeScript = $smokeScript -replace '__PROBE_PROMPT__',       $safeProbePrompt
    $smokeScript = $smokeScript -replace '__OPENAI_API_VERSION__', $OpenaiApiVersion
    $smokeScript = $smokeScript -replace '__MI_CLIENT_ID__',       $smokeMiClientId

    az vm run-command invoke `
        --resource-group $CoreResourceGroupName `
        --name $vmName `
        --command-id RunPowerShellScript `
        --scripts $smokeScript `
        --output json | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Needed 'Smoke test failed during model probe.'
        exit 1
    }

    Write-Exists 'Smoke test passed end-to-end.'
    exit 0
}

if ($Mode -eq 'ChatDual') {
    if (-not $ProbePrompt) { $ProbePrompt = "Hello! Are you online?" }

    Write-Host 'Validating Azure CLI authentication context...'
    az account show --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'No active Azure session detected - running az login...'
        az login
    }

    $subscriptionId = (az account show --query id --output tsv).Trim()
    $NameSuffix     = ($subscriptionId -replace '-', '').Substring(0, 4).ToLower()

    $config = Read-EnterpriseEnvironmentConfig -ScriptRoot $scriptRoot -EnvironmentSuffix $EnvironmentSuffix -NameSuffix $NameSuffix

    $vmName                = $config.vmName
    $keyVaultName          = $config.keyVaultName
    $CoreResourceGroupName = $config.coreResourceGroupName
    $OpenaiApiVersion      = $config.openaiApiVersion
    $vmManagedIdentityName = $config.vmManagedIdentityName

    $clientId = (az identity show --name $vmManagedIdentityName --resource-group $CoreResourceGroupName --query clientId --output tsv 2>$null)
    if (-not $clientId) {
        Write-Warning "Could not retrieve client ID for '$vmManagedIdentityName'. Test will default to system assigned identity."
        $clientId = ""
    } else {
        Write-Host "Using VM managed identity '$vmManagedIdentityName' (client ID: $clientId)..."
    }

    Write-Host "Testing dual-model chat connectivity on VM '$vmName'..."

    $dualScript = @'
$ErrorActionPreference = 'Stop'

function Get-ManagedIdentityToken {
    param([string]$Resource, [string]$ClientId)
    $uri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$Resource"
    if (-not [string]::IsNullOrWhiteSpace($ClientId)) { $uri += "&client_id=$ClientId" }
    return (Invoke-RestMethod -Headers @{ Metadata = 'true' } -Method GET -Uri $uri).access_token
}

Write-Host "Retrieving secrets from Key Vault '__KEYVAULT_NAME__'..."
$kvToken   = Get-ManagedIdentityToken -Resource 'https://vault.azure.net' -ClientId '__CLIENT_ID__'
$kvHeaders = @{ Authorization = "Bearer $kvToken" }

function Get-Secret {
    param($Name)
    try {
        return (Invoke-RestMethod -Uri "https://__KEYVAULT_NAME__.vault.azure.net/secrets/$Name`?api-version=7.4" -Headers $kvHeaders -Method GET).value
    } catch {
        Write-Host "  Warning: secret '$Name' not found or accessible."
        return $null
    }
}

$endpoint = (Get-Secret -Name 'openai-endpoint').TrimEnd('/')
$dep1     = Get-Secret -Name 'openai-deployment'
$dep2     = Get-Secret -Name 'openai-secondary-deployment'

if (-not $endpoint) { throw "Endpoint secret is missing." }
if (-not $dep1)     { throw "Primary deployment secret is missing." }

$oaiToken   = Get-ManagedIdentityToken -Resource 'https://cognitiveservices.azure.com/' -ClientId '__CLIENT_ID__'
$oaiHeaders = @{ Authorization = "Bearer $oaiToken"; 'Content-Type' = 'application/json' }
$body = @{
    messages    = @(@{ role = 'user'; content = '__PROBE_PROMPT__' })
    max_tokens  = 100
    temperature = 0.7
} | ConvertTo-Json -Depth 5

function Test-Model {
    param($DeploymentName, $Label)
    if ([string]::IsNullOrWhiteSpace($DeploymentName)) { Write-Host "${Label}: skipped (not configured)"; return }
    Write-Host "${Label} ($DeploymentName): sending request..."
    try {
        $uri  = "$endpoint/openai/deployments/$DeploymentName/chat/completions?api-version=__OPENAI_API_VERSION__"
        $resp = Invoke-RestMethod -Uri $uri -Headers $oaiHeaders -Method POST -Body $body
        Write-Host "  Response: $($resp.choices[0].message.content)"
        Write-Host "  [success]"
    } catch {
        Write-Host "  [failed] Error: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            Write-Host "  Details: $($reader.ReadToEnd())"
        } else {
            Write-Host "  Details: $_"
        }
    }
}

Test-Model -DeploymentName $dep1 -Label "Primary model"
Write-Host "-" * 40
Test-Model -DeploymentName $dep2 -Label "Secondary model"
'@

    $safeProbePrompt = $ProbePrompt -replace "'", "''"
    $dualScript = $dualScript -replace '__KEYVAULT_NAME__',      $keyVaultName
    $dualScript = $dualScript -replace '__PROBE_PROMPT__',       $safeProbePrompt
    $dualScript = $dualScript -replace '__OPENAI_API_VERSION__', $OpenaiApiVersion
    $dualScript = $dualScript -replace '__CLIENT_ID__',          $clientId

    $tempScriptFile = [System.IO.Path]::GetTempFileName() + ".ps1"
    Set-Content -Path $tempScriptFile -Value $dualScript -Encoding UTF8

    $result = az vm run-command invoke `
        --resource-group $CoreResourceGroupName `
        --name $vmName `
        --command-id RunPowerShellScript `
        --scripts "@$tempScriptFile" `
        --output json

    Remove-Item $tempScriptFile -Force -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to invoke run command on VM."
        exit 1
    }

    $outputObjects = $result | ConvertFrom-Json
    if ($outputObjects.value) {
        Write-Host "VM output:"
        Write-Host $outputObjects.value[0].message
    } else {
        Write-Host "Warning: VM output parsing failed. Raw result:"
        Write-Host $result
    }
}

Complete-ScriptLogging -Status 'completed'
