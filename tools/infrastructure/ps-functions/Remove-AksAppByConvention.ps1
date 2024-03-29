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
            $aksAppParams = @{
                HelmReleaseName     =   $InputObject.Aks.HelmReleaseName
                AppResourceGroup    =   $InputObject.AppResourceGroup.ResourceName
                Namespace           =   $InputObject.Aks.Namespace
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