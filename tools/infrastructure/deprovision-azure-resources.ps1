    <#
      .SYNOPSIS
      Uninstall the application stack that provision-azure-resoures.ps1 script provisioned
      
      .DESCRIPTION
      Provision the desired state of the application stack in Azure. This script is NOT written to be idempotent.
      Therefore there is no guarantees that the script will not error out if run multiple times.
      
      Required permission to run this script:
      * The permissions required by ps-functions/Uninstall-AzureResourceByConvention.ps1
      
    
      .PARAMETER EnvironmentName
      The name of the environment to uninstall. This value will be used to calculate conventions for that environment.

      .PARAMETER DeleteAADGroups
      Delete the Azure AD / Entra-ID groups that were created as security groups?
      Note: a missing group will be reported as an error but NOT cause the script to stop.

      .PARAMETER Login
      Perform an interactive login to azure

      .PARAMETER SubscriptionId
      The Azure subscription to act on when setting the desired state of Azure resources. If not supplied, then the subscription
      already set as the current context will used (see az account show)

      .EXAMPLE
      ./deprovision-azure-resources.ps1 -InfA Continue -EnvironmentName dev -DeleteAADGroups
   
      Description
      -----------
      Uninstall and also DELETE every resource and AAD security group
    
    #>


    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentName,
        
        [switch] $DeleteAADGroups,
        [switch] $Login,
        [string] $SubscriptionId
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/ps-functions/Invoke-Exe.ps1"
        . "$PSScriptRoot/ps-functions/Uninstall-AzureResourceByConvention.ps1"
    }
    process {
        try {

            if ($Login.IsPresent) {
                Write-Information 'Connecting to Azure AD Account...'
                Invoke-Exe { az login } | Out-Null
            }
            if ($SubscriptionId) {
                Invoke-Exe { az account set --subscription $SubscriptionId } | Out-Null
            }

            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable
            
            $uninstallParams = @{
                DeleteAADGroups                         =   $DeleteAADGroups
            }
            $convention | Uninstall-AzureResourceByConvention @uninstallParams
            
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
