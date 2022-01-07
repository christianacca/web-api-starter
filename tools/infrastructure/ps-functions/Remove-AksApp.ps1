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
        [string] $HelmChartName,

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
        try {            
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

            Write-Information "Uninstalling helm chart release '$HelmChartName' in namespace '$Namespace'..."
            Invoke-Exe { helm uninstall $HelmChartName --namespace $Namespace }  -EA Continue

            $managedIdentityName | ForEach-Object {
                $name = $_
                
                Write-Information "Deleting Pod Identity '$name' from AKS cluster '$($aks.ResourceName)'..."
                Invoke-Exe {
                    az aks pod-identity delete --name $name --namespace $Namespace -g $aks.ResourceGroupName --cluster-name $aks.ResourceName
                }  -EA Continue | Out-Null
                
                $identityClientId = Invoke-Exe {
                    az identity show -g $AppResourceGroup -n $name --query clientId -otsv
                }
                
                $rbacRole = 'Virtual Machine Contributor'
                Write-Information "Removing  RBAC role '$rbacRole' from Managed Identity '$name' for the cluster node resource group..."
                Invoke-Exe {
                    az role assignment delete --assignee $identityClientId --role $rbacRole --scope $nodeRgResourceId
                } -EA Continue | Out-Null
            }
        }
        catch
        {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}