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

        [string[]] $ManagedIdentityName = @()
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
    }
    process {
        try
        {
            $aks = $InputObject
            
            Write-Information "Getting access credentials for AKS cluster '$($aks.ResourceName)'..."
            Invoke-Exe {
                az aks get-credentials -g $aks.ResourceGroupName -n $aks.ResourceName --overwrite-existing
            } | Out-Null

            Write-Information "Getting details of Node Resource Group of AKS cluster '$($aks.ResourceName)'..."
            $nodeRg = Invoke-Exe {
                az aks show -g $aks.ResourceGroupName -n $aks.ResourceName --query nodeResourceGroup -o tsv
            }
            $nodeRgResourceId = Invoke-Exe { az group show -n $nodeRg -o tsv --query 'id' }

            $managedIdentityName | ForEach-Object {
                $name = $_

                Write-Information "Getting details of Managed Identity '$name'..."
                $identityClientId = Invoke-Exe {
                    az identity show -g $AppResourceGroup -n $name --query clientId -otsv
                }
                $identityResourceId = Invoke-Exe {
                    az identity show -g $AppResourceGroup -n $name --query id -otsv
                }

                $rbacRole = 'Virtual Machine Contributor'
                Write-Information "Assigning  RBAC role '$rbacRole' to Managed Identity '$name' for the cluster node resource group..."
                Invoke-Exe {
                    az role assignment create --role $rbacRole --assignee $identityClientId --scope $nodeRgResourceId
                } | Out-Null

                Write-Information "Adding Pod Identity '$name' to AKS cluster '$($aks.ResourceName)'..."
                Invoke-Exe {
                    az aks pod-identity add -g $aks.ResourceGroupName --cluster-name $aks.ResourceName --namespace $Namespace  --name $name --identity-resource-id $identityResourceId
                } | Out-Null
            }
        }
        catch
        {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}