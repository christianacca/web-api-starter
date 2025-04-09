    <#
      .SYNOPSIS
      Grant permissions to a user (via group membership) to access azure resources for a product
      
      .PARAMETER EnvironmentName
      The name of the environment containing the azure resources to grant access to

      .PARAMETER UserPrincipalName
      A comma delimited list of user principal names in azure to grant permissions to (via group membership).
      If not supplied, then apply the current permissions to existing Azure resources

      .PARAMETER AccessLevel
      The access level to grant (eg development). Note: 'GPS / support-tier-1' is an alias of 'support-tier-1'
      and 'App Admin / support-tier-2' is an alias of 'support-tier-2'

      .PARAMETER $SubProductName
      The name of the sub product to grant access

      .PARAMETER Login
      Perform an interactive login to azure

      .PARAMETER SubscriptionId
      The Azure subscription to act on when setting the desired state of Azure resources. If not supplied, then the subscription
      already set as the current context will used (see Get-AzContext, Select-Subscription)
    #>

    
    [CmdletBinding(DefaultParameterSetName = 'Main')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Main')]
        [string] $EnvironmentName,

        [Parameter(ParameterSetName = 'Main')]
        [string] $UserPrincipalName,

        [Parameter(Mandatory, ParameterSetName = 'Main')]
        [ValidateSet('development', 'support-tier-1', 'support-tier-2', 'GPS / support-tier-1', 'App Admin / support-tier-2')]
        [string] $AccessLevel,
        
        [string] $SubProductName,

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
            $params = @{
                InputObject             = $convention
                UserPrincipalName       = $UserPrincipalName -split ','
                AccessLevel             = $AccessLevel
                SubProductName          = $SubProductName
                ApplyCurrentPermissions = -not($UserPrincipalName)
            }
            Grant-AzureEnvironmentAccess @params
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
