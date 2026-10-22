function Remove-NonFlexFunctionApp {
    <#
      .SYNOPSIS
      Delete a Function App that is not hosted on the Flex Consumption plan, and its hosting plan when left empty

      .DESCRIPTION
      Azure does not support migrating an existing Function App in-place onto the Flex Consumption plan. The app has to
      be deleted and re-created under the same name. This function performs the delete step so that the ARM/bicep
      deployment that follows can create the Flex Consumption app and plan.

      Durable Functions state, queues and tables live in the storage account, which is not touched. Orchestrations
      resume once the re-created app (same name, therefore same task hub) is running.

      .PARAMETER InputObject
      A Function App returned by Get-NonFlexFunctionApp

      .EXAMPLE
      'func-clc-was-dev-internalapi' | Get-NonFlexFunctionApp -ResourceGroupName rg-dev-was-eastus2 | Remove-NonFlexFunctionApp -InformationAction Continue
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject] $InputObject
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            $app = $InputObject
            if ($PSCmdlet.ShouldProcess($app.Name, "Delete Function App hosted on '$($app.PlanTier)' plan to allow re-creation on Flex Consumption")) {
                Write-Information "  Deleting Function App '$($app.Name)' (hosted on '$($app.PlanTier)' plan) so it can be re-created on Flex Consumption..."
                Remove-AzResource -ResourceId $app.ResourceId -Force | Out-Null
            }

            if ($app.PlanResourceId -and $app.PlanSiteCount -le 1 -and $PSCmdlet.ShouldProcess($app.PlanName, 'Delete now empty hosting plan')) {
                Write-Information "  Deleting hosting plan '$($app.PlanName)'..."
                Remove-AzResource -ResourceId $app.PlanResourceId -Force | Out-Null
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
