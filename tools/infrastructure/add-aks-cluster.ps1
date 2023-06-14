    [CmdletBinding()]
    param(
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',

        [switch] $CreateAzureContainerRegistry,

        [switch] $Login,
        [string] $SubscriptionId
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        . "$PSScriptRoot/ps-functions/Get-ResourceConvention.ps1"
        . "$PSScriptRoot/ps-functions/Invoke-Exe.ps1"
        
        function Add-AksCluser {
            param(
                [Hashtable] $Cluster,
                [string] $AksRegistryName,
                [switch] $CreateAcr
            )

            $rgName = $Cluster.ResourceGroupName
            $akaName = $Cluster.ResourceName
            $rg = Invoke-Exe { az group list --query "[?name=='$rgName']" | ConvertFrom-Json -Depth 10 }
            if (-not($rg)) {
                Write-Information "Creating Resource Group '$rgName'"
                Invoke-Exe { az group create --location eastus -n $rgName } | Out-Null
            }

            if ($CreateAcr) {
                Write-Information "Creating Azure Container Registry '$AksRegistryName'"
                Invoke-Exe { az acr create -n $AksRegistryName -g $rgName --sku basic }
            }
            
            Write-Information "Creating AKS Cluster '$akaName' in resource group '$rgName'"
            Invoke-Exe {
                az aks create -g $rgName -n $akaName --network-plugin azure --enable-addons http_application_routing --node-count 1 --node-vm-size Standard_B2s --enable-managed-identity --attach-acr $AksRegistryName --generate-ssh-keys --enable-oidc-issuer --enable-workload-identity
            } | Out-Null
        }
    }
    process {
        try {

            if ($Login.IsPresent) {
                Write-Information 'Connecting to Azure AD Account...'
                Invoke-Exe { az login } | Out-Null
            }
            if ($SubscriptionId) {
                Invoke-Exe { az account set --subscription $SubscriptionId } | Out-Null
            }

            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable
            $aks = $convention.Aks;
            Add-AksCluser -Cluster $aks.Primary -AksRegistryName $aks.RegistryName -CreateAcr:$CreateAzureContainerRegistry
            if ($aks.Failover) {
                Add-AksCluser -Cluster $aks.Failover -AksRegistryName $aks.RegistryName
            }
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
