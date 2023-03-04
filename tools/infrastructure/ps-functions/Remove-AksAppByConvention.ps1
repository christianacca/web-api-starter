function Remove-AksAppByConvention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject,

        [switch] $PodIdentityOnly
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/Remove-AksApp.ps1"
    }
    process {
        try {
            $managedIdentityName = $InputObject.SubProducts.Values |
                Where-Object { $_.Type -eq 'AksPod' } |
                Select-Object -ExpandProperty ManagedIdentity |
                Select-Object -ExpandProperty Name

            $aksAppParams = @{
                HelmChartName       =   $InputObject.Aks.HelmChartName
                AppResourceGroup    =   $InputObject.AppResourceGroup.ResourceName
                Namespace           =   $InputObject.Aks.Namespace
                ManagedIdentityName =   $managedIdentityName
            }

            $clusters = @($InputObject.Aks.Primary; $InputObject.Aks.Failover) |
                Where-Object { $_ } |
                ForEach-Object { [PsCustomObject]$_ }

            $clusters | Remove-AksApp @aksAppParams -PodIdentityOnly:$PodIdentityOnly
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}