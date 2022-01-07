    <#
      .SYNOPSIS
      Uninstall the application stack that provision-azure-resoures.ps1 script provisioned
      
      .DESCRIPTION
      Provision the desired state of the application stack in Azure. This script is NOT written to be idempotent.
      Therefore there is no guarantees that the script will not error out if run multiple times.
      
      Required permission to run this script:
      
      * Azure AD 'Groups administrator'
      * The permissions required by ps-functions/Install-FunctionAppAzureResource.ps1
      * The permissions required by ps-functions/Install-SqlAzureResource.ps1
      
    
      .PARAMETER EnvironmentName
      The name of the environment to uninstall. This value will be used to calculate conventions for that environment.

      .PARAMETER DeleteSqlAADGroups
      Delete the Azure AD groups that were created as security groups for Azure SQL?
      Note: a missing group will be reported as an error but NOT cause the script to stop.

      .PARAMETER DeleteResourceGroup
      Delete the Azure resource group rather than just remove all the resources found in that group?

      .PARAMETER UninstallDataResource
      Remove not only the application related Azure resources but also the data related resources as well?
      Note: you must supply this flag if both application and data Azure resources are contained in the same resource group.
      In otherwords it is not possible for this script to remove just application resources when they are co-located with data.

      .PARAMETER UninstallAksApp
      Uninstall the AKS release for the application? This flag only makes sense if your application is deployed to AKS via helm

      .PARAMETER Login
      Perform an interactive login to azure

      .PARAMETER SubscriptionId
      The Azure subscription to act on when setting the desired state of Azure resources. If not supplied, then the subscription
      already set as the current context will used (see az account show)
    
      .EXAMPLE
      ./provision-azure-resources.ps1 -InformationAction Continue
    
      Description
      -----------
      Creates all the Azure resources for the 'dev' environment, displaying to the console details of the task execution.

      .EXAMPLE
      ./deprovision-azure-resources.ps1 -InfA Continue -UninstallDataResource  -DeleteResourceGroup -DeleteSqlAADGroups -UninstallAksApp
   
      Description
      -----------
      Uninstall and also DELETE every resource
    
    #>


    [CmdletBinding()]
    param(
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',
        
        [switch] $DeleteSqlAADGroups,
        [switch] $DeleteResourceGroup,
        [switch] $UninstallDataResource,
        [switch] $UninstallAksApp,
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
                DeleteSqlAADGroups                      =   $DeleteSqlAADGroups
                DeleteResourceGroup                     =   $DeleteResourceGroup
                UninstallDataResource                   =   $UninstallDataResource
                UninstallAksApp                         =   $UninstallAksApp
                DeprovisionResourceGroupTemplatePath    =   "$PSScriptRoot/arm-templates/deprovision-resource-group.bicep"
            }
            $convention | Uninstall-AzureResourceByConvention @uninstallParams
            
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
