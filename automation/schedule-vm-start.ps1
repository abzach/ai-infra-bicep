param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $ResourceGroupName,
    [Parameter(Mandatory)] [string] $VmName,
    [Parameter(Mandatory)] [string] $AutomationIdentityClientId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Disable-AzContextAutosave -Scope Process | Out-Null
$context = (Connect-AzAccount -Identity -AccountId $AutomationIdentityClientId).Context
$context = Set-AzContext -SubscriptionId $SubscriptionId -DefaultProfile $context

$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -Status -DefaultProfile $context
$powerState = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' } | Select-Object -First 1).Code

if ($powerState -eq 'PowerState/running') {
    Write-Output "VM '$VmName' is already running."
    return
}

Write-Output "Starting VM '$VmName' from state '$powerState'."
Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -DefaultProfile $context | Out-Null

$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -Status -DefaultProfile $context
$powerState = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' } | Select-Object -First 1).Code
if ($powerState -ne 'PowerState/running') {
    throw "VM '$VmName' did not reach the running state. Current state: '$powerState'."
}

Write-Output "VM '$VmName' is running."
