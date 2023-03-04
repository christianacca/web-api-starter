    [CmdletBinding()]
    param(
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',

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
                [string] $AksRegistryName
            )

            $rgName = $Cluster.ResourceGroupName
            $rg = Invoke-Exe { az group list --query "[?name=='$rgName']" | ConvertFrom-Json -Depth 10 }
            if (-not($rg)) {
                Write-Information "Creating Resource Group '$rg'"
                Invoke-Exe { az group create --location eastus -n $convention.Aks.Primary.ResourceGroupName } | Out-Null
            }
            
            Write-Information "Creating AKS Cluster '$($Cluster.ResourceName)' in resource group '$rgName'"
            Invoke-Exe {
                az aks create -g $rgName -n $Cluster.ResourceName --network-plugin azure --enable-addons http_application_routing --node-count 1 --node-vm-size Standard_B2s --enable-managed-identity --attach-acr $AksRegistryName --generate-ssh-keys
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
            Add-AksCluser -Cluster ($convention.Aks.Primary) -AksRegistryName ($convention.Aks.RegistryName)
            if ($convention.Aks.Failover) {
                Add-AksCluser -Cluster ($convention.Aks.Failover) -AksRegistryName ($convention.Aks.RegistryName)
            }            
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
