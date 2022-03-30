function Get-ScriptDependencyList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Hashtable[]] $Module
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            $list = $Module | ForEach-Object {
                '{0}:{1}' -f $_.Name, $_.MinimumVersion
            }
            $list -join ','
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}