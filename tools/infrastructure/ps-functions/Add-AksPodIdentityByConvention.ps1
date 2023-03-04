function Add-AksPodIdentityByConvention {
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

        . "$PSScriptRoot/Add-AksPodIdentity.ps1"
    }
    process {
        try {
            $managedIdentity = $InputObject.SubProducts.Values |
                Where-Object { $_.Type -eq 'AksPod' } |
                Select-Object -ExpandProperty ManagedIdentity
            
            $podIdentityParams = @{
                AppResourceGroup    =   $InputObject.AppResourceGroup.ResourceName
                Namespace           =   $InputObject.Aks.Namespace
                ManagedIdentity     =   $managedIdentity
            }

            $clusters = @($InputObject.Aks.Primary; $InputObject.Aks.Failover) |
                Where-Object { $_ } |
                ForEach-Object { [PsCustomObject]$_ }

            $clusters | Add-AksPodIdentity @podIdentityParams
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}