    [CmdletBinding()]
    param(
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',

        [switch] $PodIdentityOnly,
        
        [switch] $Login,
        [string] $SubscriptionId
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/ps-functions/Get-ResourceConvention.ps1"
        . "$PSScriptRoot/ps-functions/Remove-AksAppByConvention.ps1"
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
            $convention | Remove-AksAppByConvention -PodIdentityOnly:$PodIdentityOnly
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
