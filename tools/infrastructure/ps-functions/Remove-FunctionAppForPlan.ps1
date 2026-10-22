function Remove-FunctionAppForPlan {
    <#
      .SYNOPSIS
      Delete the Function App(s) hosted on an App Service plan, then the plan itself

      .DESCRIPTION
      Used when a plan's operating system has to change (see Get-ArmOsChangeConflict). Azure can't change it in place, so
      the app and plan are deleted and the deployment that follows re-creates them.

      Refuses to delete anything when the plan hosts a site that is not a Function App.

      Durable Functions state, queues and tables live in the storage account, which is not touched. When the re-created
      app has the same name (and so the same task hub), orchestrations continue once it is running. Work that was running
      when the app was deleted runs again from the start.

      .PARAMETER PlanName
      The name of the App Service plan

      .PARAMETER ResourceGroupName
      The resource group containing the plan

      .EXAMPLE
      'func-clc-was-dev-internalapi' | Remove-FunctionAppForPlan -ResourceGroupName rg-dev-was-eastus2 -InformationAction Continue
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $PlanName,

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
            $plan = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Web/serverfarms' -Name $PlanName -EA SilentlyContinue
            if (-not $plan) {
                Write-Information "  INFO | Hosting plan '$PlanName' does not exist; nothing to delete"
                return
            }

            $sites = @(
                Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Web/sites' -ExpandProperties |
                    Where-Object { $_.Properties.serverFarmId -ieq $plan.ResourceId }
            )

            $notFunctionApps = @($sites | Where-Object { $_.Kind -notlike '*functionapp*' })
            if ($notFunctionApps) {
                throw "Hosting plan '$PlanName' also hosts sites that are not Function Apps ($($notFunctionApps.Name -join ', ')); delete the plan and its sites manually"
            }

            foreach ($site in $sites) {
                if ($PSCmdlet.ShouldProcess($site.Name, 'Delete Function App')) {
                    Write-Information "  Deleting Function App '$($site.Name)'..."
                    Remove-AzResource -ResourceId $site.ResourceId -Force | Out-Null
                }
            }

            if ($PSCmdlet.ShouldProcess($PlanName, 'Delete hosting plan')) {
                Write-Information "  Deleting hosting plan '$PlanName'..."
                Remove-AzResource -ResourceId $plan.ResourceId -Force | Out-Null
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
