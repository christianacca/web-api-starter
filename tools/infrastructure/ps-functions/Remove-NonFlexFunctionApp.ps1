function Remove-NonFlexFunctionApp {
    <#
      .SYNOPSIS
      Delete a Function App that is not on the Flex Consumption plan, and its plan, so a deployment can re-create it on Flex

      .DESCRIPTION
      Azure can't change the OS of an existing hosting plan (Y1 is Windows, Flex is Linux), so the app has to be deleted
      and re-created under the same name. Does nothing for an app that doesn't exist or is already on Flex Consumption.
      Durable Functions state lives in the storage account, which is not touched.

      .PARAMETER BeforeDelete
      Run once, before the first delete. Use it to check that the deployment that follows can succeed

      .EXAMPLE
      'func-clc-was-dev-internalapi' | Remove-NonFlexFunctionApp -ResourceGroupName rg-dev-was-eastus2 -BeforeDelete { ... }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $ResourceGroupName,

        [ScriptBlock] $BeforeDelete
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        $beforeDeleteDone = $false
    }
    process {
        try {
            $site = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Web/sites' -Name $Name -ExpandProperties -EA SilentlyContinue
            $plan = if ($site) { Get-AzResource -ResourceId $site.Properties.serverFarmId -EA SilentlyContinue }
            if (-not $plan -or $plan.Sku.Tier -eq 'FlexConsumption') {
                return
            }

            if ($BeforeDelete -and -not $beforeDeleteDone -and -not $WhatIfPreference) {
                & $BeforeDelete
                $beforeDeleteDone = $true
            }
            if ($PSCmdlet.ShouldProcess($Name, "Delete Function App on '$($plan.Sku.Tier)' plan so it can be re-created on Flex Consumption")) {
                Write-Information "  Deleting Function App '$Name' and its plan (on '$($plan.Sku.Tier)') so it can be re-created on Flex Consumption..."
                Remove-AzResource -ResourceId $site.ResourceId -Force | Out-Null
                Remove-AzResource -ResourceId $plan.ResourceId -Force | Out-Null
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
