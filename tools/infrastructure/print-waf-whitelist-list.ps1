<#
    .SYNOPSIS
    Output the WAF whitelist rules that are required for each DNS zone

    .PARAMETER AsArray
    Return the output as an array of objects rather than a formatted list?
    

    .EXAMPLE
    ./tools/infrastructure/print-waf-whitelist-list.ps1
    
    Description
    -----------
    Returns the WAF rules as a formatted list. EG:
    
    Zone Name: was.clcsoftware.com
    Rule Name: Web Api Starter - OWASP Core Ruleset Skips
    Rules to skip: OWASP Core Ruleset
    Rule Expression...
    
    starts_with(lower(http.request.uri.path), "/api/breeze/") or 
    starts_with(lower(http.request.uri.path), "/api/internal/")

    .EXAMPLE
    ./tools/infrastructure/print-waf-whitelist-list.ps1 -AsArray | fl *
    
    Description
    -----------
    Returns the WAF rules as an array which is then further transformed into list formtted by default by powershell. EG:
    
    ZoneName    : was.clcsoftware.com
    RuleName    : Web Api Starter - OWASP Core Ruleset Skips
    RulesToSkip : OWASP Core Ruleset
    RuleExpr    : starts_with(lower(http.request.uri.path), "/api/breeze/") or 
                  starts_with(lower(http.request.uri.path), "/api/internal/")


#>

param(
    [switch] $AsArray
)
begin {
    Set-StrictMode -Version 'Latest'
    $callerEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
}
process {
    try {

        $environments = & "$PSScriptRoot/get-product-environment-names.ps1"
        
        $zoneTable = $environments |
            ForEach-Object {
                & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $_ -AsHashtable
            } -pv convention |
            ForEach-Object {
                $convention.SubProducts.Api.WafWhitelistRules
            } |
            Select-Object @{ n='Env'; e={ $convention.EnvironmentName} }, @{ n='Product'; e={ $convention.Product.Name} }, * |
            Sort-Object Env, Path |
            Group-Object -Property { '{0}:{1}:{2}' -f $_.Product, $_.ZoneName, $_.RulesToSkip } -AsString -AsHashTable
        
        $zoneTable = $zoneTable ?? @{}

        $exprJoin = ' or {0}' -f [Environment]::NewLine
        $result = $zoneTable.GetEnumerator() | ForEach-Object {
            $keyParts = $_.key.Split(':')
            [PsCustomObject]@{
                ZoneName    = $keyParts[1]
                RuleName    = '{0} - {1} Skips' -f $keyParts[0], $keyParts[2]
                RulesToSkip = $keyParts[2]
                RuleExpr    = ($_.value | Select-Object -Exp Expression -Unique) -join $exprJoin
            }
        }

        if ($AsArray) {
            $result
        } else {
            $result | ForEach-Object {
                Write-Host "Zone Name: $($_.ZoneName)" -ForegroundColor Blue
                Write-Host "Rule Name: $($_.RuleName)" -ForegroundColor Blue
                Write-Host "Rules to skip: $($_.RulesToSkip)" -ForegroundColor Blue
                Write-Host "Rule Expression..." -ForegroundColor Blue
                Write-Host ''
                Write-Host $_.RuleExpr
                Write-Host ''
                Write-Host '----------------------------' -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Error -ErrorRecord $_ -EA $callerEA
    }
}
