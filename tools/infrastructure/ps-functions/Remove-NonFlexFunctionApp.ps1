function Remove-NonFlexFunctionApp {
    <#
      .SYNOPSIS
      Delete a Function App, and its hosting plan, when that Function App is not hosted on the Flex Consumption plan

      .DESCRIPTION
      Azure does not support migrating an existing Function App in-place onto the Flex Consumption plan. The app has to
      be deleted and re-created under the same name. This function performs the delete step so that the ARM/bicep
      deployment that follows can create the Flex Consumption app and plan.

      The function is idempotent: when the Function App does not exist or is already hosted on a Flex Consumption plan,
      nothing is changed.

      .PARAMETER Name
      The name of the Function App (and the hosting plan, which by convention shares the same name)

      .PARAMETER ResourceGroupName
      The resource group containing the Function App

      .EXAMPLE
      Remove-NonFlexFunctionApp -Name func-clc-was-dev-internalapi -ResourceGroupName rg-dev-was-eastus2 -InformationAction Continue
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $ResourceGroupName
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            $site = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Web/sites' -Name $Name -ExpandProperties -EA SilentlyContinue
            if (-not $site) {
                Write-Information "  INFO | Function App '$Name' does not exist; nothing to migrate"
                return
            }

            $planId = $site.Properties.serverFarmId
            $plan = Get-AzResource -ResourceId $planId -ExpandProperties -EA SilentlyContinue
            $planTier = if ($plan) { $plan.Sku.Tier } else { $null }
            if ($planTier -eq 'FlexConsumption') {
                Write-Information "  INFO | Function App '$Name' is already hosted on a Flex Consumption plan"
                return
            }

            if ($PSCmdlet.ShouldProcess($Name, "Delete Function App hosted on '$planTier' plan to allow re-creation on Flex Consumption")) {
                Write-Information "  Deleting Function App '$Name' (hosted on '$planTier' plan) so it can be re-created on Flex Consumption..."
                Remove-AzResource -ResourceId $site.ResourceId -Force | Out-Null
            }

            $remainingSites = if ($plan) { $plan.Properties.numberOfSites - 1 } else { 0 }
            if ($plan -and $remainingSites -le 0 -and $PSCmdlet.ShouldProcess($plan.Name, 'Delete now empty hosting plan')) {
                Write-Information "  Deleting hosting plan '$($plan.Name)'..."
                Remove-AzResource -ResourceId $plan.ResourceId -Force | Out-Null
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
