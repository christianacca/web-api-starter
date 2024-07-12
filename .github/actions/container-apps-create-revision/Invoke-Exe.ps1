function Invoke-Exe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock] $ScriptBlock
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            Write-Verbose "Executing: $ScriptBlock"
            Invoke-Command $ScriptBlock
            if ($LASTEXITCODE -ne 0) {
                $exitCode = $LASTEXITCODE
                $global:LASTEXITCODE = $null # reset so that runtimes like github actions doesn't fail the entire script
                throw "Command failed with exit code $exitCode; Cmd: $ScriptBlock"
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
