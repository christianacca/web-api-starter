<#
    .SYNOPSIS
    Return information about the deployed infrastructure
      
#>


[CmdletBinding(DefaultParameterSetName = 'Values')]
param(
    [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject', Position = 1)]
    [ValidateNotNull()]
    [Alias('Convention')]
    [Hashtable] $InputObject,

    [Parameter(Mandatory, ParameterSetName = 'Values', Position = 1)]
    [string] $EnvironmentName,
    
    [switch] $AsHashtable
)
begin {
    Set-StrictMode -Version 'Latest'
    $callerEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    . "./tools/infrastructure/ps-functions/Invoke-Exe.ps1"
}
process {
    try {

        $InputObject = if ($null -eq $InputObject) {
            & "./tools/infrastructure/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable
        } else {
            $InputObject
        }

        $EnvironmentName = if (-not($EnvironmentName)) {
            $InputObject.EnvironmentName
        } else {
            $EnvironmentName
        }

        Invoke-Exe {
            az config set extension.use_dynamic_install=yes_without_prompt    
        }
        
        $appInsights = $InputObject.SubProducts.AppInsights
        $api = $InputObject.SubProducts.Api
        $funcApp = $InputObject.SubProducts.InternalApi
        $appResourceGroup = $InputObject.AppResourceGroup.ResourceName

        $metadata = Invoke-Exe { az group show -n $appResourceGroup } | ConvertFrom-Json | Select-Object -Exp tags

        $apiManagedIdentity = Invoke-Exe {
            az identity show -g $appResourceGroup -n $api.ManagedIdentity.Primary
        } | ConvertFrom-Json

        $funcManagedIdentity = Invoke-Exe {
            az identity show -g $appResourceGroup -n $funcApp.ManagedIdentity
        } | ConvertFrom-Json
        
        $appInsightsCnnString = Invoke-Exe {
            az monitor app-insights component show -a $appInsights.ResourceName -g $appInsights.ResourceGroupName  -o tsv --query 'connectionString'
        } -EA SilentlyContinue
        
        $results = @{
            Api             =   @{
                ManagedIdentityClientId     =   $apiManagedIdentity.clientId
                ManagedIdentityObjectId     =   $apiManagedIdentity.principalId
            }
            AppInsights     =   @{
                ConnectionString            =   $appInsightsCnnString ?? ''
            }
            InternalApi     =   @{
                ManagedIdentityClientId     =   $funcManagedIdentity.clientId
                ManagedIdentityObjectId     =   $funcManagedIdentity.principalId
            }
            Version         =   $metadata | Select-Object -Exp Version -EA Ignore
        }

        if ($AsHashtable) {
            $results
        }
        else {
            $results | ConvertTo-Json -Depth 100
        }
        
    }
    catch {
        Write-Error -ErrorRecord $_ -EA $callerEA
    }
}
