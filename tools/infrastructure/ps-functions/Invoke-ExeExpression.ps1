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
                $exitCode = $LASTEXITCODE
                $global:LASTEXITCODE = $null # reset so that runtimes like github actions doesn't fail the entire script
                throw "Command failed with exit code $exitCode; Cmd: $Command"
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}