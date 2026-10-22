function Get-NonFlexFunctionApp {
    <#
      .SYNOPSIS
      Return the Function Apps that exist but are not hosted on the Flex Consumption plan

      .DESCRIPTION
      Returns an object for each named Function App that exists and is hosted on a plan other than Flex Consumption.
      Function Apps that don't exist, or are already on Flex Consumption, return nothing. Pipe the output to
      Remove-NonFlexFunctionApp to delete them.

      .PARAMETER Name
      The name of the Function App

      .PARAMETER ResourceGroupName
      The resource group containing the Function App

      .EXAMPLE
      'func-clc-was-dev-internalapi' | Get-NonFlexFunctionApp -ResourceGroupName rg-dev-was-eastus2
    #>
    [CmdletBinding()]
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
                Write-Information "  INFO | Function App '$Name' does not exist"
                return
            }

            $plan = Get-AzResource -ResourceId $site.Properties.serverFarmId -ExpandProperties -EA SilentlyContinue
            $planTier = if ($plan) { $plan.Sku.Tier } else { $null }
            if ($planTier -eq 'FlexConsumption') {
                Write-Information "  INFO | Function App '$Name' is already hosted on a Flex Consumption plan"
                return
            }

            [PSCustomObject]@{
                Name                =   $Name
                ResourceId          =   $site.ResourceId
                PlanName            =   if ($plan) { $plan.Name } else { $null }
                PlanResourceId      =   if ($plan) { $plan.ResourceId } else { $null }
                PlanTier            =   $planTier
                PlanSiteCount       =   if ($plan) { $plan.Properties.numberOfSites } else { 0 }
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
