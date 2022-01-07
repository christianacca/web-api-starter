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
                throw "Command failed with exit code $LASTEXITCODE; Cmd: $ScriptBlock"
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
