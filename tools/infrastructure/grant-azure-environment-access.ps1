    <#
      .SYNOPSIS
      Grant permissions to a user to access azure resources for product
      
      .PARAMETER EnvironmentName
      The name of the environment containing the azure resources to grant access to

      .PARAMETER UserPrincipalName
      The name of the user principal in azure to grant permissions to. If not supplied, then apply RBAC permissions
      to all existing users

      .PARAMETER AccessLevel
      The access level to grant (development, support-tier-1, support-tier-2)

      .PARAMETER Login
      Perform an interactive login to azure

      .PARAMETER SubscriptionId
      The Azure subscription to act on when setting the desired state of Azure resources. If not supplied, then the subscription
      already set as the current context will used (see Get-AzContext, Select-Subscription)
    #>

    
    [CmdletBinding(DefaultParameterSetName = 'Main')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Main')]
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName,

        [Parameter(ParameterSetName = 'Main')]
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
        . "$PSScriptRoot/ps-functions/Grant-AzureEnvironmentAccess.ps1"
        . "$PSScriptRoot/ps-functions/Install-ScriptDependency.ps1"
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
            $convention | Grant-AzureEnvironmentAccess -UserPrincipalName $UserPrincipalName -AccessLevel $AccessLevel
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
