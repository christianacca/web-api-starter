<#
    .SYNOPSIS
    Output as a table DNS records for the custom domains of the deployed infrastructure

    .PARAMETER AsArray
    Return the output as an array of objects rather than a formatted table?

    .PARAMETER EnvironmentName
    Name(s) of the environment to get the DNS records for. Default is all environments.
#>

param(
    [ValidateSet('dev', 'qa', 'rel', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac', '*')]
    [string[]] $EnvironmentName = '*',
    
    [ValidateSet('CNAME', 'TXT', '*')]
    [string] $RecordType = '*',
    
    [switch] $Login,
    [switch] $AsArray
)
begin {
    Set-StrictMode -Version 'Latest'
    $callerEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    . "./tools/infrastructure/ps-functions/Invoke-Exe.ps1"
}
process {
    try {

        $environments = if ($EnvironmentName -eq '*') {
            & "$PSScriptRoot/get-product-environment-names.ps1"
        } else {
            $EnvironmentName
        }
        $records = if ($RecordType -eq '*') {
            'CNAME', 'TXT'
        } else {
            $RecordType
        }

        if ($Login) {
            Write-Information 'Connecting to Azure AD Account...'
            Invoke-Exe { az login } | Out-Null
        }
        
        $result = $environments |
            ForEach-Object {
                & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $_ -AsHashtable
            } -pv convention |
            ForEach-Object {
                
                $apiDomain = ($convention.SubProducts.Api.HostName).Split('.')
                $apiZoneName = ($apiDomain | Select-Object -Skip 1) -join '.'

                if ($records -contains 'CNAME') {
                    [PsCustomObject]@{
                        Service         =   'Api'
                        ZoneName        =   $apiZoneName
                        RecordType      =   'CNAME'
                        RecordName      =   $apiDomain[0]
                        RecordContent   =   '{0}.trafficmanager.net' -f $convention.SubProducts.ApiTrafficManager.ResourceName
                    }
                }

                if ($records -contains 'TXT') {
                    $subscriptionId = (& "./.github/actions/azure-login/set-azure-connection-variables.ps1" -EnvironmentName $_.EnvironmentName -AsHashtable).subscriptionId
                    $domainVerificationId = Invoke-Exe {
                        az rest --uri "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.App/getCustomDomainVerificationId?api-version=2023-08-01-preview" --method POST
                    }
                    [PsCustomObject]@{
                        Service         =   'Api'
                        ZoneName        =  $apiZoneName
                        RecordType      =   'TXT'
                        RecordName      =   'asuid.{0}' -f $apiDomain[0]
                        RecordContent   =   $domainVerificationId.Replace('"', '')
                    }
                }
        
            } |
            Select-Object @{ n='Env'; e={ $convention.EnvironmentName} }, *

        if ($AsArray) {
            $result
        } else {
            $result | Format-Table -AutoSize
        }
    }
    catch {
        Write-Error -ErrorRecord $_ -EA $callerEA
    }
}
