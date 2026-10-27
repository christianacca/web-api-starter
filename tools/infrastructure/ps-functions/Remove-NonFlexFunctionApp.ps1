function Remove-NonFlexFunctionApp {
    <#
      .SYNOPSIS
      Delete a Function App that is not on the Flex Consumption plan, and its plan, so a deployment can re-create it on Flex

      .DESCRIPTION
      Azure can't change the OS of an existing hosting plan (Y1 is Windows, Flex is Linux), so the app has to be deleted
      and re-created under the same name. Does nothing for an app that doesn't exist or is already on Flex Consumption.
      Durable Functions state lives in the storage account, which is not touched.

      .PARAMETER TemplateFile
      The template of the deployment that will re-create the app. It is validated once, before the first delete, so that
      a deployment that is bound to fail doesn't leave the environment without its Function App

      .PARAMETER ParametersFile
      The parameters file for TemplateFile

      .EXAMPLE
      'func-clc-was-dev-internalapi' | Remove-NonFlexFunctionApp -ResourceGroupName rg-dev-was-eastus2 -TemplateFile main.json -ParametersFile main.params.json
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory)]
        [string] $TemplateFile,

        [Parameter(Mandatory)]
        [string] $ParametersFile
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        $validated = $false
    }
    process {
        try {
            $site = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Web/sites' -Name $Name -ExpandProperties -EA SilentlyContinue
            $plan = if ($site) { Get-AzResource -ResourceId $site.Properties.serverFarmId -EA SilentlyContinue }
            if (-not $plan -or $plan.Sku.Tier -eq 'FlexConsumption') {
                return
            }

            if (-not $validated -and -not $WhatIfPreference) {
                Invoke-Exe {
                    az deployment group validate --resource-group $ResourceGroupName --template-file $TemplateFile --parameters "@$ParametersFile" --output none
                } -EA Stop
                $validated = $true
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
