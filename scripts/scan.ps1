param(
    [string] $TemplatePath = (Join-Path $PSScriptRoot '..\bicep\templates\main.bicep')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-TemplateExpressionValue {
    param(
        [Parameter(Mandatory)] [object] $Value,
        [Parameter(Mandatory)] [object] $Template
    )

    $parameterMatch = [regex]::Match([string] $Value, "^\[parameters\('([^']+)'\)\]$")
    if (-not $parameterMatch.Success) {
        return $Value
    }

    $parameter = $Template.parameters.PSObject.Properties[$parameterMatch.Groups[1].Value]
    if ($null -eq $parameter -or $null -eq $parameter.Value.PSObject.Properties['defaultValue']) {
        return $null
    }

    return $parameter.Value.defaultValue
}

function Get-TemplateResources {
    param([Parameter(Mandatory)] [object] $Template)

    $resources = [System.Collections.Generic.List[object]]::new()
    $walkTemplate = {
        param([object] $CurrentTemplate)

        $templateResources = $CurrentTemplate.PSObject.Properties['resources']
        if ($null -eq $templateResources) {
            return
        }

        $resourceValue = $templateResources.Value
        $resourceItems = if (
            $resourceValue -is [pscustomobject] -and
            $null -eq $resourceValue.PSObject.Properties['type']
        ) {
            @($resourceValue.PSObject.Properties.Value)
        } else {
            @($resourceValue)
        }

        foreach ($resource in $resourceItems) {
            $resource | Add-Member -NotePropertyName '_scanTemplate' -NotePropertyValue $CurrentTemplate -Force
            $resources.Add($resource)
            $propertiesProperty = $resource.PSObject.Properties['properties']
            if ($null -ne $propertiesProperty) {
                $nestedTemplateProperty = $propertiesProperty.Value.PSObject.Properties['template']
                if ($null -ne $nestedTemplateProperty) {
                    $nestedParametersProperty = $propertiesProperty.Value.PSObject.Properties['parameters']
                    if ($null -ne $nestedParametersProperty -and $null -ne $nestedTemplateProperty.Value.PSObject.Properties['parameters']) {
                        foreach ($nestedParameter in $nestedTemplateProperty.Value.parameters.PSObject.Properties) {
                            $passedParameter = $nestedParametersProperty.Value.PSObject.Properties[$nestedParameter.Name]
                            if ($null -eq $passedParameter -or $null -eq $passedParameter.Value.PSObject.Properties['value']) {
                                continue
                            }

                            $resolvedValue = Resolve-TemplateExpressionValue -Value $passedParameter.Value.value -Template $CurrentTemplate
                            if ($null -ne $resolvedValue) {
                                $nestedParameter.Value | Add-Member -NotePropertyName defaultValue -NotePropertyValue $resolvedValue -Force
                            }
                        }
                    }
                    & $walkTemplate $nestedTemplateProperty.Value
                }
            }
        }
    }

    & $walkTemplate $Template
    return $resources
}

function Get-ResourceScanTemplate {
    param(
        [Parameter(Mandatory)] [object] $Resource,
        [Parameter(Mandatory)] [object] $FallbackTemplate
    )

    $scanTemplateProperty = $Resource.PSObject.Properties['_scanTemplate']
    if ($null -ne $scanTemplateProperty -and $null -ne $scanTemplateProperty.Value) {
        return $scanTemplateProperty.Value
    }

    return $FallbackTemplate
}

function Get-ResourcesOfType {
    param(
        [Parameter(Mandatory)] [System.Collections.Generic.List[object]] $Resources,
        [Parameter(Mandatory)] [string] $Type
    )

    return @($Resources | Where-Object {
        $null -ne $_.PSObject.Properties['type'] -and $_.type -eq $Type -and $null -ne $_.PSObject.Properties['properties']
    })
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

    $resolvedValue = Resolve-TemplateExpressionValue -Value $Value -Template $Template
    if ($resolvedValue -is [bool]) {
        return $resolvedValue
    }

    return $false
}

function Resolve-StringTemplateValue {
    param(
        [Parameter(Mandatory)] [object] $Value,
        [Parameter(Mandatory)] [object] $Template
    )

    $resolvedValue = Resolve-TemplateExpressionValue -Value $Value -Template $Template
    if ($null -eq $resolvedValue) {
        return ''
    }

    return [string]$resolvedValue
}

function Resolve-IntegerTemplateValue {
    param(
        [Parameter(Mandatory)] [object] $Value,
        [Parameter(Mandatory)] [object] $Template
    )

    if ($Value -is [int]) {
        return $Value
    }

    $resolvedValue = Resolve-TemplateExpressionValue -Value $Value -Template $Template
    if ($null -eq $resolvedValue) {
        return $null
    }

    if ([string]$resolvedValue -notmatch '^-?\d+$') {
        return $null
    }

    return [int]$resolvedValue
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
    Test-Rule -Condition ($storageAccount.properties.publicNetworkAccess -eq 'Disabled') -Message 'Storage public network access is disabled.' -Failures $failures
    Test-Rule -Condition ($storageAccount.properties.networkAcls.defaultAction -eq 'Deny') -Message 'Storage network ACL defaults to deny.' -Failures $failures
}

$vaults = Get-ResourcesOfType -Resources $resources -Type 'Microsoft.KeyVault/vaults'
Test-Rule -Condition ($vaults.Count -gt 0) -Message 'A Key Vault is defined.' -Failures $failures
foreach ($vault in $vaults) {
    Test-Rule -Condition ($vault.properties.enableRbacAuthorization -eq $true) -Message 'Key Vault uses Azure RBAC authorization.' -Failures $failures
    Test-Rule -Condition ($vault.properties.publicNetworkAccess -eq 'Disabled') -Message 'Key Vault public network access is disabled.' -Failures $failures
    Test-Rule -Condition ($vault.properties.networkAcls.defaultAction -eq 'Deny') -Message 'Key Vault network ACL defaults to deny.' -Failures $failures
}

$cognitiveServicesAccounts = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.CognitiveServices/accounts')
$openAiAccounts = @($cognitiveServicesAccounts | Where-Object { $_.kind -eq 'OpenAI' })
Test-Rule -Condition ($openAiAccounts.Count -eq 1) -Message 'An Azure OpenAI account is defined.' -Failures $failures
foreach ($openAiAccount in $openAiAccounts) {
    Test-Rule -Condition ($openAiAccount.properties.publicNetworkAccess -eq 'Disabled') -Message 'Azure OpenAI public network access is disabled.' -Failures $failures
    Test-Rule -Condition (Resolve-BooleanTemplateValue -Value $openAiAccount.properties.disableLocalAuth -Template $template) -Message 'Azure OpenAI local authentication is disabled.' -Failures $failures
}

$foundryAccounts = @($cognitiveServicesAccounts | Where-Object { $_.kind -eq 'AIServices' })
Test-Rule -Condition ($foundryAccounts.Count -eq 1) -Message 'A Microsoft Foundry AIServices account is defined.' -Failures $failures
foreach ($foundryAccount in $foundryAccounts) {
    Test-Rule -Condition ($foundryAccount.properties.publicNetworkAccess -eq 'Disabled') -Message 'Foundry public network access is disabled.' -Failures $failures
    Test-Rule -Condition (Resolve-BooleanTemplateValue -Value $foundryAccount.properties.disableLocalAuth -Template $template) -Message 'Foundry local authentication is disabled.' -Failures $failures
    Test-Rule -Condition ($foundryAccount.properties.networkAcls.defaultAction -eq 'Deny') -Message 'Foundry network ACL defaults to deny.' -Failures $failures
}

$foundryProjects = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.CognitiveServices/accounts/projects')
Test-Rule -Condition ($foundryProjects.Count -eq 1) -Message 'A Microsoft Foundry child project is defined.' -Failures $failures

$foundryCapabilityHosts = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts')
Test-Rule -Condition ($foundryCapabilityHosts.Count -eq 1) -Message 'A Microsoft Foundry Agent capability host is defined.' -Failures $failures
foreach ($foundryCapabilityHost in $foundryCapabilityHosts) {
    Test-Rule -Condition ($foundryCapabilityHost.properties.capabilityHostKind -eq 'Agents') -Message 'Foundry capability host kind is Agents.' -Failures $failures
}

$searchServices = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Search/searchServices')
Test-Rule -Condition ($searchServices.Count -eq 1) -Message 'An Azure AI Search service is defined.' -Failures $failures
foreach ($searchService in $searchServices) {
    Test-Rule -Condition ($searchService.properties.publicNetworkAccess -eq 'disabled') -Message 'Azure AI Search public network access is disabled.' -Failures $failures
    Test-Rule -Condition (Resolve-BooleanTemplateValue -Value $searchService.properties.disableLocalAuth -Template $template) -Message 'Azure AI Search local authentication is disabled.' -Failures $failures
}

$compiledTemplateText = [string]::Join("`n", @($templateJson))
Test-Rule -Condition ($compiledTemplateText -match 'Microsoft\.App/environments') -Message 'A dedicated subnet is delegated to Microsoft.App/environments for Foundry Agent Service.' -Failures $failures

$automationAccounts = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Automation/automationAccounts')
Test-Rule -Condition ($automationAccounts.Count -eq 1) -Message 'One Automation Account is defined.' -Failures $failures
foreach ($automationAccount in $automationAccounts) {
    Test-Rule -Condition ($automationAccount.identity.type -eq 'UserAssigned') -Message 'Automation uses only a user-assigned managed identity.' -Failures $failures
    Test-Rule -Condition ($automationAccount.properties.disableLocalAuth -eq $true) -Message 'Automation local authentication is disabled.' -Failures $failures
    Test-Rule -Condition ($automationAccount.properties.publicNetworkAccess -eq $false) -Message 'Automation public network access is disabled.' -Failures $failures
}

$automationCredentials = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Automation/automationAccounts/credentials')
Test-Rule -Condition ($automationCredentials.Count -eq 0) -Message 'No Automation credential assets are defined.' -Failures $failures

$automationWebhooks = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Automation/automationAccounts/webhooks')
Test-Rule -Condition ($automationWebhooks.Count -eq 0) -Message 'No Automation webhooks are defined.' -Failures $failures

$postgresServers = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.DBforPostgreSQL/flexibleServers')
Test-Rule -Condition ($postgresServers.Count -eq 1) -Message 'A PostgreSQL Flexible Server is defined.' -Failures $failures
foreach ($postgresServer in $postgresServers) {
    Test-Rule -Condition ($postgresServer.sku.tier -eq 'Burstable') -Message 'PostgreSQL Flexible Server uses the Burstable compute tier.' -Failures $failures
    Test-Rule -Condition ($postgresServer.properties.highAvailability.mode -eq 'Disabled') -Message 'PostgreSQL Flexible Server has high availability disabled.' -Failures $failures
    Test-Rule -Condition ($postgresServer.properties.backup.geoRedundantBackup -eq 'Disabled') -Message 'PostgreSQL Flexible Server backup is not geo-redundant.' -Failures $failures
    Test-Rule -Condition ($postgresServer.properties.storage.autoGrow -eq 'Disabled') -Message 'PostgreSQL Flexible Server storage auto-grow is disabled.' -Failures $failures
    Test-Rule -Condition (-not [string]::IsNullOrWhiteSpace([string]$postgresServer.properties.network.delegatedSubnetResourceId)) -Message 'PostgreSQL Flexible Server is integrated into the VNet through a delegated subnet (no public endpoint).' -Failures $failures
}

$staticWebApps = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Web/staticSites')
Test-Rule -Condition ($staticWebApps.Count -eq 1) -Message 'A Static Web App is defined.' -Failures $failures
foreach ($staticWebApp in $staticWebApps) {
    $staticWebAppTemplate = Get-ResourceScanTemplate -Resource $staticWebApp -FallbackTemplate $template
    $staticWebAppSkuName = Resolve-StringTemplateValue -Value $staticWebApp.sku.name -Template $staticWebAppTemplate
    $staticWebAppSkuTier = Resolve-StringTemplateValue -Value $staticWebApp.sku.tier -Template $staticWebAppTemplate
    Test-Rule -Condition ($staticWebAppSkuName -eq 'Free' -and $staticWebAppSkuTier -eq 'Free') -Message 'Static Web App uses the Free hosting plan.' -Failures $failures
}

$cosmosAccounts = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.DocumentDB/databaseAccounts')
Test-Rule -Condition ($cosmosAccounts.Count -eq 1) -Message 'A Cosmos DB account is defined.' -Failures $failures
foreach ($cosmosAccount in $cosmosAccounts) {
    Test-Rule -Condition ($cosmosAccount.properties.enableFreeTier -in @($true, $false)) -Message 'Cosmos DB free-tier setting is explicit.' -Failures $failures
    Test-Rule -Condition ($cosmosAccount.properties.publicNetworkAccess -eq 'Disabled') -Message 'Cosmos DB public network access is disabled.' -Failures $failures
    Test-Rule -Condition ($cosmosAccount.properties.disableLocalAuth -eq $true) -Message 'Cosmos DB local key authentication is disabled.' -Failures $failures
}

$cosmosDatabases = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases')
Test-Rule -Condition ($cosmosDatabases.Count -eq 1) -Message 'A Cosmos DB SQL database is defined.' -Failures $failures
foreach ($cosmosDatabase in $cosmosDatabases) {
    $cosmosDatabaseTemplate = Get-ResourceScanTemplate -Resource $cosmosDatabase -FallbackTemplate $template
    $throughput = Resolve-IntegerTemplateValue -Value $cosmosDatabase.properties.options.throughput -Template $cosmosDatabaseTemplate
    Test-Rule -Condition ($null -ne $throughput -and $throughput -ge 400 -and $throughput -le 1000) -Message 'Cosmos DB uses manual provisioned throughput within the free-tier RU/s allowance.' -Failures $failures
}

$cosmosContainers = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers')
Test-Rule -Condition ($cosmosContainers.Count -eq 1) -Message 'A Cosmos DB SQL container is defined.' -Failures $failures
foreach ($cosmosContainer in $cosmosContainers) {
    Test-Rule -Condition ($cosmosContainer.properties.resource.partitionKey.paths.Count -eq 1) -Message 'Cosmos DB container has a partition key.' -Failures $failures
}

$apiManagementServices = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.ApiManagement/service')
Test-Rule -Condition ($apiManagementServices.Count -eq 1) -Message 'An API Management service is defined.' -Failures $failures
foreach ($apiManagementService in $apiManagementServices) {
    $apiManagementTemplate = Get-ResourceScanTemplate -Resource $apiManagementService -FallbackTemplate $template
    $apiManagementSkuName = Resolve-StringTemplateValue -Value $apiManagementService.sku.name -Template $apiManagementTemplate
    Test-Rule -Condition ($apiManagementSkuName -eq 'Consumption' -and $apiManagementService.sku.capacity -eq 0) -Message 'API Management uses the Consumption tier.' -Failures $failures
}

$appServicePlans = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Web/serverfarms')
Test-Rule -Condition ($appServicePlans.Count -eq 1) -Message 'An App Service plan is defined.' -Failures $failures
foreach ($appServicePlan in $appServicePlans) {
    $appServicePlanTemplate = Get-ResourceScanTemplate -Resource $appServicePlan -FallbackTemplate $template
    $appServiceSkuName = Resolve-StringTemplateValue -Value $appServicePlan.sku.name -Template $appServicePlanTemplate
    Test-Rule -Condition ($appServiceSkuName -eq 'F1' -and $appServicePlan.sku.tier -eq 'Free') -Message 'App Service plan uses the F1 Free tier.' -Failures $failures
}

$appServices = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Web/sites')
Test-Rule -Condition ($appServices.Count -eq 1) -Message 'An App Service web app is defined.' -Failures $failures
foreach ($appService in $appServices) {
    Test-Rule -Condition ($appService.properties.httpsOnly -eq $true) -Message 'App Service requires HTTPS.' -Failures $failures
    Test-Rule -Condition ($appService.properties.siteConfig.minTlsVersion -eq '1.2') -Message 'App Service requires TLS 1.2 or later.' -Failures $failures
    Test-Rule -Condition ($appService.properties.siteConfig.ftpsState -eq 'Disabled') -Message 'App Service FTP/FTPS access is disabled.' -Failures $failures
}

$automationJobSchedules = @(Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Automation/automationAccounts/jobSchedules')
Test-Rule -Condition ($automationJobSchedules.Count -eq 0) -Message 'Automation job links are deferred until runbooks are published.' -Failures $failures

$roleAssignments = Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Authorization/roleAssignments'
$vmContributorRoleId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'
$automationVmRoles = @($roleAssignments | Where-Object { [string]$_.properties.roleDefinitionId -match $vmContributorRoleId })
Test-Rule -Condition ($automationVmRoles.Count -eq 1) -Message 'Automation has exactly one Virtual Machine Contributor assignment.' -Failures $failures
foreach ($automationVmRole in $automationVmRoles) {
    Test-Rule -Condition ([string]$automationVmRole.scope -match 'Microsoft.Compute/virtualMachines') -Message 'Automation VM Contributor is scoped to the VM.' -Failures $failures
}

$networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'
$automationNsgRoles = @($roleAssignments | Where-Object { [string]$_.properties.roleDefinitionId -match $networkContributorRoleId })
Test-Rule -Condition ($automationNsgRoles.Count -eq 1) -Message 'Automation has exactly one Network Contributor assignment.' -Failures $failures
foreach ($automationNsgRole in $automationNsgRoles) {
    Test-Rule -Condition ([string]$automationNsgRole.scope -match 'Microsoft.Network/networkSecurityGroups') -Message 'Automation Network Contributor is scoped to the jumpbox NSG.' -Failures $failures
}

$diagnosticSettings = Get-ResourcesOfType -Resources $resources -Type 'Microsoft.Insights/diagnosticSettings'
Test-Rule -Condition ($diagnosticSettings.Count -ge 2) -Message 'Azure OpenAI and Microsoft Foundry diagnostic settings are present.' -Failures $failures
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