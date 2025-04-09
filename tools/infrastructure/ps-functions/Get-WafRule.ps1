function Get-WafRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentName,

        [Parameter(Mandatory)]
        [hashtable] $Domain,
        
        [Parameter(Mandatory, ValueFromPipeline)]
        [hashtable] $WafWhitelist,

        [Parameter(Mandatory)]
        [string] $HostName
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        . "$PSScriptRoot/Get-IsEnvironmentProdLike.ps1"
        . "$PSScriptRoot/Get-PublicHostName.ps1"
        . "$PSScriptRoot/Get-CloudflareWafRuleExpr.ps1"

        $isEnvProdLike = Get-IsEnvironmentProdLike $EnvironmentName
        $isHostHeaderFilterRequired = $Domain['SubDomainLevel'] -eq 2 -or(!$isEnvProdLike -and($Domain['NonProdSubDomain'] -ne 'UseProductDomain'))
        $hostHeaderWafFilter = $isHostHeaderFilterRequired ? $HostName : $null
        $zoneName = ((Get-PublicHostName $EnvironmentName @Domain).Split('.') | Select-Object -Skip 1) -join '.'
    }
    process {
        try {
            if ($WafWhitelist.Type -ne 'cloudflare') {
                throw "Unsupported WAF type: $($WafWhitelist.Type)"
            }
            $WafWhitelist.Path | Get-CloudflareWafRuleExpr -HostHeader $hostHeaderWafFilter | Select-Object `
                @{ n='ZoneName'; e={ $zoneName } }, `
                @{ n='RulesToSkip'; e={ $WafWhitelist.RulesToSkip ?? 'All' } }, `
                *
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}