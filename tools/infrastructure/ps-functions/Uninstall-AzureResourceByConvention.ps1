function Uninstall-AzureResourceByConvention {
    <#
      .SYNOPSIS
      Uninstall the application stack using conventions to derive the resources that require uninstalling
      
      .DESCRIPTION
      Uninstall the application stack using conventions to derive the resources that require uninstalling.
      This script is NOT written to be idempotent. Therefore there is no guarantees that the script will not error
      out if run multiple times.
      
      Required permission to run this script:
      
      * Azure 'Contributor' and 'User Access Administrator' on resource group
      * Azure AD 'Groups administrator' or owner of each Azure AD group to be deleted
      * Owner of Azure AD group 'sg.aad.role.custom.azuresqlauthentication'
      
    
      .PARAMETER InputObject
      The conventions that determine the resources that require uninstalling

      .PARAMETER DeleteAADGroups
      Delete the Azure AD groups that were created as security groups?
      Note: a missing group will be reported as an error but NOT cause the script to stop.

      .PARAMETER UninstallAksApp
      Uninstall the AKS release for the application? This flag only makes sense if your application is deployed to AKS via helm
    
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
 
      $convention | Uninstall-AzureResourceByConvention -DeleteAADGroups -UninstallAksApp
    
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject,

        [switch] $DeleteAADGroups,
        [switch] $UninstallAksApp
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/Invoke-Exe.ps1"
        . "$PSScriptRoot/Remove-ADAppRegistration.ps1"
        . "$PSScriptRoot/Remove-AksAppByConvention.ps1"
    }
    process {
        try {
            $appResourceGroup = $InputObject.AppResourceGroup.ResourceName

            $functionAppName = $InputObject.SubProducts.Values | 
                Where-Object { $_.Type -eq 'FunctionApp' } |
                Select-Object -Exp ResourceName

            $functionAppName | Remove-ADAppRegistration
            
            if ($UninstallAksApp) {
                $InputObject | Remove-AksAppByConvention   
            }

            if ($DeleteAADGroups) {
                $groups = @(
                $InputObject.SubProducts.Values | ForEach-Object { $_['AadSecurityGroup'] } | Select-Object -ExpandProperty Name
                $convention.SubProducts.Values | ForEach-Object { $_['TeamGroups'] } | Select-Object -ExpandProperty Values
                    $InputObject.TeamGroups.Values
                )
                $groups | ForEach-Object {
                    $groupName = $_
                    Write-Information "Deleting Azure AD group '$groupName'"
                    Invoke-Exe { az ad group delete --group $groupName } -EA Continue | Out-Null
                }
            }

            Write-Information "Deleting resource group '$appResourceGroup'"
            Invoke-Exe { az group delete --name $appResourceGroup --yes } | Out-Null

            $purgableKeyVault = $InputObject.SubProducts.Values |
                Where-Object { $_.Type -eq 'KeyVault' -and -not($_.EnablePurgeProtection) } |
                Select-Object -Exp ResourceName
            $purgableKeyVault | ForEach-Object {
                $name = $_
                Write-Information "Purging Azure KeyVault '$name'"
                Invoke-Exe { az keyvault purge -n $name --no-wait }
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}