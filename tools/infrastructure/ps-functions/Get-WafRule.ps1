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

        . "$PSScriptRoot/Get-PublicHostName.ps1"
        . "$PSScriptRoot/Get-CloudflareWafRuleExpr.ps1"

        # Host header filtering is only needed when SubDomainLevel is 1 (all envs share one zone)
        # SubDomainLevel 2 and 3 use wildcard DNS zones, so no host filtering is needed
        $isHostHeaderFilterRequired = $Domain['SubDomainLevel'] -eq 1
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