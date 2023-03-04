    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name = 'dev-aks-local',
        
        [string] $ResourceGroupName = $Name,

        [Parameter(Mandatory)]
        [string] $AcrName,
        
        [string] $AcrResourceGroupName = $AcrName,
        
        [switch] $CreateAcr
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "./tools/infrastructure/ps-functions/Invoke-Exe.ps1"
    }
    process {
        try {
            Invoke-Exe { az group create --name $ResourceGroupName --location eastus }
            
            if ($CreateAcr) {
                Invoke-Exe { az group create --name $AcrResourceGroupName --location eastus }
                Invoke-Exe { az acr create -n $AcrName -g $AcrResourceGroupName --sku basic }
            }
            
            Invoke-Exe { 
                az aks create -g $ResourceGroupName -n $Name --network-plugin azure --enable-addons http_application_routing --node-count 1 --node-vm-size Standard_B2s --enable-managed-identity --attach-acr $AcrName --generate-ssh-keys
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
