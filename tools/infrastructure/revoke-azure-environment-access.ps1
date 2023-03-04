    <#
      .SYNOPSIS
      Revoke permissions to a user to access azure resources for product
      
      .PARAMETER EnvironmentName
      The name of the environment containing the azure resources to revoke access to

      .PARAMETER UserPrincipalName
      The name of the user principal in azure to revoke permissions to

      .PARAMETER AccessLevel
      The access level to revoke (development, support-tier-1, support-tier-2)
    #>

    
    [CmdletBinding(DefaultParameterSetName = 'Main')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Main')]
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName,

        [Parameter(Mandatory, ParameterSetName = 'Main')]
        [string] $UserPrincipalName,

        [Parameter(Mandatory, ParameterSetName = 'Main')]
        [ValidateSet('development', 'support-tier-1', 'support-tier-2')]
        [string] $AccessLevel,

        [switch] $Login,
        [string] $SubscriptionId,

        [Parameter(Mandatory, ParameterSetName = "ListModule")]
        [switch] $ListModuleRequirementsOnly,
        [switch] $SkipInstallModules
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        $WarningPreference = 'Continue'

        . "$PSScriptRoot/ps-functions/Get-AzModuleInfo.ps1"
        . "$PSScriptRoot/ps-functions/Get-ScriptDependencyList.ps1"
        . "$PSScriptRoot/ps-functions/Install-ScriptDependency.ps1"
        . "$PSScriptRoot/ps-functions/Revoke-AzureEnvironmentAccess.ps1"
        . "$PSScriptRoot/ps-functions/Set-AzureAccountContext.ps1"
    }
    process {
        try {
            $modules = @(Get-AzModuleInfo)
            if ($ListModuleRequirementsOnly) {
                Get-ScriptDependencyList -Module $modules
                return
            } else {
                Install-ScriptDependency -ImportOnly:$SkipInstallModules -Module $modules
            }

            Set-AzureAccountContext -Login:$Login -SubscriptionId $SubscriptionId

            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable
            $convention | Revoke-AzureEnvironmentAccess -UserPrincipalName $UserPrincipalName -AccessLevel $AccessLevel
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
