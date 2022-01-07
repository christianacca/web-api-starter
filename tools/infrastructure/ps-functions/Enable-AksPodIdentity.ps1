function Enable-AksPodIdentity {
    [CmdletBinding(DefaultParameterSetName = 'Values')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')]
        [ValidateNotNull()]
        [PsCustomObject] $InputObject,
        
        [Parameter(Mandatory, ParameterSetName = 'Values')]
        [string] $ClusterName,

        [Parameter(ParameterSetName = 'Values')]
        [string] $ResourceGroup = $ClusterName
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/Invoke-Exe.ps1"

        if (-not($InputObject)) {
            $InputObject =  @{
                ResourceName        =   $ClusterName
                ResourceGroupName   =   $ResourceGroup
            }
        }

        try {
            Write-Information "Register Pod identity feature in az-cli..."
            Invoke-Exe {
                az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
            }
            Invoke-Exe {
                az extension add --name aks-preview
                az extension update --name aks-preview
            }
        }
        catch {
            Write-Error "$_`n$( $_.ScriptStackTrace )" -EA $callerEA
        }
    }
    process {
        try {
            $aks = $InputObject

            Write-Information "Getting access credentials for AKS cluster '$($aks.ResourceName)'..."
            Invoke-Exe {
                az aks get-credentials -g $aks.ResourceGroupName -n $aks.ResourceName --overwrite-existing
            } | Out-Null

            Write-Information "Enabling Pod Identity to AKS cluster '$($aks.ResourceName)'..."
            Invoke-Exe { az aks update -g $aks.ResourceGroupName -n $aks.ResourceName --enable-pod-identity }
        }
        catch {
            Write-Error "$_`n$( $_.ScriptStackTrace )" -EA $callerEA
        }
    }
}