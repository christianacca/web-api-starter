function Invoke-ExeExpression {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Command
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            Write-Verbose "Executing: $Command"
            Invoke-Expression $Command
            if ($LASTEXITCODE -ne 0) {
                throw "Command failed with exit code $LASTEXITCODE; Cmd: $Command"
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}