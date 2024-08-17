<#
    .SYNOPSIS
    Get the Azure subscription ID for every product environment
#>

$loginActionScript = "$PSScriptRoot/../.././.github/actions/azure-login/set-azure-connection-variables.ps1"
$environments = & "$PSScriptRoot/get-product-environment-names.ps1"

$environments | ForEach-Object -Begin { $result = @{} } -Process {
    $env = $_
    $subscriptionId = (& $loginActionScript -EnvironmentName $env -AsHashtable).subscriptionId
    $result[$env] = $subscriptionId
}
$result
