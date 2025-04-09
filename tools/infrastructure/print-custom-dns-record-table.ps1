<#
    .SYNOPSIS
    Output as a table DNS records for the custom domains of the deployed infrastructure

    .PARAMETER AsArray
    Return the output as an array of objects rather than a formatted table?

    .PARAMETER ComponentName
    Component name(s) of the azure container app to get the DNS records for. Default is all container appss.

    .PARAMETER EnvironmentName
    Name(s) of the environment to get the DNS records for. Default is all environments.
#>

param(
    [string[]] $EnvironmentName = '*',
    
    [string[]] $ComponentName,
    
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
    
    function GetDnsRecords(
        [string] $EvnName,
        [hashtable] $App,
        [hashtable] $SubProducts
    ) {
        $domain = ($App.HostName).Split('.')
        $zoneName = ($domain | Select-Object -Skip 1) -join '.'
        $tmProfile = $SubProducts.GetEnumerator() |
            Where-Object { $_.value.Type -eq 'TrafficManager' -and $_.value.Target -eq $App.Name } |
            Select-Object -First 1 -ExpandProperty Value

        if ($records -contains 'CNAME') {
            [PsCustomObject]@{
                Service         =   $App.Name
                ZoneName        =   $zoneName
                RecordType      =   'CNAME'
                RecordName      =   $domain[0]
                RecordContent   =   '{0}.trafficmanager.net' -f $tmProfile.ResourceName
            }
        }

        if ($records -contains 'TXT') {
            $subscriptionId = (& "./.github/actions/azure-login/set-azure-connection-variables.ps1" -EnvironmentName $EvnName -AsHashtable).subscriptionId
            $domainVerificationId = Invoke-Exe {
                az rest --uri "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.App/getCustomDomainVerificationId?api-version=2023-08-01-preview" --method POST
            }
            [PsCustomObject]@{
                Service         =   $App.Name
                ZoneName        =  $zoneName
                RecordType      =   'TXT'
                RecordName      =   'asuid.{0}' -f $domain[0]
                RecordContent   =   $domainVerificationId.Replace('"', '')
            }
        }
    }
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
                $convention.SubProducts.GetEnumerator() |
                    Where-Object { $_.value.Type -eq 'AcaApp' -and($_.key -in $ComponentName -or $null -eq $ComponentName)} |
                    Select-Object -ExpandProperty Value
            } -pv acaApp |
            ForEach-Object {
                GetDnsRecords -App $acaApp -EvnName $convention.EnvironmentName -SubProducts $convention.SubProducts
            } |
            Select-Object @{ n='Env'; e={ $convention.EnvironmentName} }, *

        if ($AsArray) {
            $result
        } else {
            $result | Format-Table -AutoSize
        }
    }
    catch {
        Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
    }
}
