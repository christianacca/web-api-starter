function Add-AksPodIdentity {
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
        [string] $AppResourceGroup,

        [Parameter(Mandatory)]
        [string] $Namespace,

        [Hashtable[]] $ManagedIdentity = @()
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
        try
        {
            $aks = $InputObject
            
            Write-Information "Getting access credentials for AKS cluster '$($aks.ResourceName)'..."
            Invoke-Exe {
                az aks get-credentials -g $aks.ResourceGroupName -n $aks.ResourceName --overwrite-existing
            } | Out-Null

            $identities = $ManagedIdentity | Select-Object -pv identity |
                Select-Object -ExpandProperty Name |
                Select-Object @{ n='Selector'; e={ $identity.BindingSelector } }, @{ n='Name'; e={ $_ } }

            $identities | ForEach-Object {
                $name = $_.Name
                $selector = $_.Selector

                Write-Information "Getting details of Managed Identity '$name'..."
                $identityResourceId = Invoke-Exe {
                    az identity show -g $AppResourceGroup -n $name --query id -otsv
                }

                Write-Information "Adding Pod Identity '$name' to AKS cluster '$($aks.ResourceName)'..."
                Invoke-Exe {
                    az aks pod-identity add -g $aks.ResourceGroupName --cluster-name $aks.ResourceName --namespace $Namespace  --name $name --identity-resource-id $identityResourceId --binding-selector $selector
                } | Out-Null
            }
        }
        catch
        {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}