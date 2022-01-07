function Uninstall-AzureResourceByConvention {
    <#
      .SYNOPSIS
      Uninstall the application stack using conventions to derive the resources that require uninstalling
      
      .DESCRIPTION
      Uninstall the application stack using conventions to derive the resources that require uninstalling.
      This script is NOT written to be idempotent. Therefore there is no guarantees that the script will not error
      out if run multiple times.
      
      Required permission to run this script:
      
      * Azure AD 'Groups administrator'
      * The permissions required by Install-FunctionAppAzureResource.ps1
      * The permissions required by Install-SqlAzureResource.ps1
      
    
      .PARAMETER InputObject
      The conventions that determine the resources that require uninstalling

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

      .PARAMETER DeprovisionResourceGroupTemplatePath
      The path to the bicep template that will be used to deprovision resources within the resource group

      .PARAMETER AdditionalRBACRoleRemoval
      A script block that will called with the name of the managed identity. Use this script block to remove
      any other RBAC role that is assigned to the managed identity that are not defined by conventions
    
      .EXAMPLE
      $conventionsParams = @{
          ProductName             =   'myapp'
          EnvironmentName         =   $EnvironmentName
          SubProducts             =   @{
              Sql         =   @{ Type = 'SqlServer' }
              Db          =   @{ Type = 'SqlDatabase' }
              Func        =   @{ Type = 'FunctionApp' }
              Api         =   @{ Type = 'AksPod' }
          }
      }
      $convention = Get-ResourceConvention @conventionsParams -AsHashtable
 
      $uninstallParams = @{
          DeleteSqlAADGroups                      =   $true
          DeleteResourceGroup                     =   $true
          UninstallDataResource                   =   $true
          UninstallAksApp                         =   $true
          DeprovisionResourceGroupTemplatePath    =   ./deprovision-resource-group.bicep
      }
      $convention | Uninstall-AzureResourceByConvention @uninstallParams
    
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject,

        [switch] $DeleteSqlAADGroups,
        [switch] $DeleteResourceGroup,
        [switch] $UninstallDataResource,
        [switch] $UninstallAksApp,

        [Parameter(Mandatory)]
        [string] $DeprovisionResourceGroupTemplatePath,
    
        [ScriptBlock] $AdditionalRBACRoleRemoval
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/Invoke-Exe.ps1"
        . "$PSScriptRoot/Remove-ADAppRegistration.ps1"
        . "$PSScriptRoot/Remove-AksAppByConvention.ps1"
        . "$PSScriptRoot/Remove-RBACRoleFromManagedIdentity.ps1"

        function Uninstall-ResourceGroup {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string] $Name
            )
            process {
                if ($DeleteResourceGroup) {
                    Write-Information "Deleting resource group '$Name'"
                    Invoke-Exe { az group delete --name $Name --yes } | Out-Null
                } else {
                    Write-Information "Deleting all resources within resource group '$Name'"
                    Invoke-Exe {
                        az deployment group create -g $Name -f $DeprovisionResourceGroupTemplatePath --mode Complete
                    } | Out-Null
                }
            }
        }
    }
    process {
        try {
            $appResourceGroup = $InputObject.AppResourceGroup.ResourceName
            $dataResourceGroup = $InputObject.DataResourceGroup.ResourceName

            if (-not($UninstallDataResource) -and($appResourceGroup -eq $dataResourceGroup)) {
                throw "Cannot deprovision just the application resources as both the data and app resources are in the same resource group. To uninstall data resources supply -UninstallDataResource"
            }

            $functionAppName = $InputObject.SubProducts.GetEnumerator() |
                Where-Object { $_.Value.Type -eq 'FunctionApp' } |
                Select-Object -ExpandProperty Value |
                Select-Object -ExpandProperty ResourceName

            $functionAppName | Remove-ADAppRegistration

            $managedIdentityName = $InputObject.SubProducts.GetEnumerator() |
                Where-Object { $_.Value.Type -in 'AksPod','FunctionApp' -and $_.Value.ManagedIdentity } |
                Select-Object -ExpandProperty Value |
                Select-Object -ExpandProperty ManagedIdentity

            $managedIdentityName | ForEach-Object {
                Remove-RBACRoleFromManagedIdentity -Name ($_) -ManagedIdentityResourceGroup $appResourceGroup -EA Continue
                if ($AdditionalRBACRoleRemoval) {
                    Invoke-Command $AdditionalRBACRoleRemoval -ArgumentList $_ -EA Continue | Out-Null
                }
            }

            if ($UninstallAksApp) {
                $InputObject | Remove-AksAppByConvention
            }

            if ($DeleteSqlAADGroups -and $InputObject.SubProducts.Db) {
                $groups = @(
                    $InputObject.SubProducts.Db.DatabaseGroupUser.Name
                    $InputObject.SubProducts.Sql.ADAdminGroupName
                )
                $groups | ForEach-Object {
                    $groupName = $_
                    Write-Information "Deleting Azure AD group '$groupName'"
                    Invoke-Exe { az ad group delete --group $groupName } -EA Continue | Out-Null
                }
            }

            Uninstall-ResourceGroup $appResourceGroup

            if ($UninstallDataResource -and($dataResourceGroup -ne $appResourceGroup)) {
                Uninstall-ResourceGroup $dataResourceGroup
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}