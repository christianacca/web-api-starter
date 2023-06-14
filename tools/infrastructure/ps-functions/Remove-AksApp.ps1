function Remove-AksApp {
    [CmdletBinding(DefaultParameterSetName = 'Values')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')]
        [ValidateNotNull()]
        [PsCustomObject] $InputObject,
        
        [Parameter(Mandatory, ParameterSetName = 'Values')]
        [string] $ClusterName,
        
        [Parameter(ParameterSetName = 'Values')]
        [string] $AksResourceGroup = $ClusterName,

        [Parameter(Mandatory)]
        [string] $HelmReleaseName,

        [Parameter(Mandatory)]
        [string] $AppResourceGroup,

        [Parameter(Mandatory)]
        [string] $Namespace
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/Invoke-Exe.ps1"

        if (-not($InputObject)) {
            $InputObject =  @{
                ResourceName        =   $ClusterName
                ResourceGroupName   =   $AksResourceGroup
            }
        }

        Write-Information "Configuring auto-install of az-preview extension..."
        Invoke-Exe {
            az config set extension.use_dynamic_install=yes_without_prompt
        } | Out-Null
    }
    process {
        try {            
            $aks = $InputObject

            Write-Information "Getting access credentials for AKS cluster '$($aks.ResourceName)'..."
            Invoke-Exe {
                az aks get-credentials -g $aks.ResourceGroupName -n $aks.ResourceName --overwrite-existing
            } | Out-Null

            Write-Information "Uninstalling helm chart release '$HelmReleaseName' in namespace '$Namespace'..."
            Invoke-Exe { helm uninstall $HelmReleaseName --namespace $Namespace }  -EA Continue
        }
        catch
        {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}