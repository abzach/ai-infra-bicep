param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $ResourceGroupName,
    [Parameter(Mandatory)] [string] $NetworkSecurityGroupName,
    [Parameter(Mandatory)] [string] $AutomationIdentityClientId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Disable-AzContextAutosave -Scope Process | Out-Null
$context = (Connect-AzAccount -Identity -AccountId $AutomationIdentityClientId).Context
$context = Set-AzContext -SubscriptionId $SubscriptionId -DefaultProfile $context

$networkSecurityGroup = Get-AzNetworkSecurityGroup `
    -ResourceGroupName $ResourceGroupName `
    -Name $NetworkSecurityGroupName `
    -DefaultProfile $context

$ruleName = 'allow-rdp-deployer'
$rule = $networkSecurityGroup.SecurityRules | Where-Object Name -EQ $ruleName | Select-Object -First 1
if ($null -eq $rule) {
    Write-Output "NSG rule '$ruleName' is already absent."
    return
}

Remove-AzNetworkSecurityRuleConfig `
    -Name $ruleName `
    -NetworkSecurityGroup $networkSecurityGroup `
    -DefaultProfile $context | Out-Null
Set-AzNetworkSecurityGroup -NetworkSecurityGroup $networkSecurityGroup -DefaultProfile $context | Out-Null

Write-Output "Deleted temporary NSG rule '$ruleName'."