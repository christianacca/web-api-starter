function Remove-AksAppByConvention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/Remove-AksApp.ps1"
    }
    process {
        try {
            $managedIdentityName = $InputObject.SubProducts.GetEnumerator() |
                Where-Object { $_.Value.Type -eq 'AksPod' -and $_.Value.ManagedIdentity } |
                Select-Object -ExpandProperty Value |
                Select-Object -ExpandProperty ManagedIdentity

            $aksAppParams = @{
                HelmChartName       =   $InputObject.Aks.HelmChartName
                AppResourceGroup    =   $InputObject.AppResourceGroup.ResourceName
                Namespace           =   $InputObject.Aks.Namespace
                ManagedIdentityName =   $managedIdentityName
            }

            $clusters = @($InputObject.Aks.Primary; $InputObject.Aks.Failover) |
                Where-Object { $_ } |
                ForEach-Object { [PsCustomObject]$_ }

            $clusters | Remove-AksApp @aksAppParams
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}