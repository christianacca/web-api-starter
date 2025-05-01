<#
    .SYNOPSIS
    Get the Azure subscription ID for every product environment
#>

param(
    [ValidateSet('subscriptionId', 'clientId', 'principalId', 'tenantId')]
    [string] $PropertyName
)

$loginActionScript = "$PSScriptRoot/../.././.github/actions/azure-login/set-azure-connection-variables.ps1"
$environments = & "$PSScriptRoot/get-product-environment-names.ps1"

$environments | ForEach-Object -Begin { $result = @{} } -Process {
    $env = $_
    $connectionInfo = & $loginActionScript -EnvironmentName $env -AsHashtable
    $result[$env] = $PropertyName ? $connectionInfo[$PropertyName] : $connectionInfo
} -End { $result }
