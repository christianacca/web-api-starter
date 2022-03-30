function Install-ScriptDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Hashtable[]] $Module,
    
        [switch] $ImportOnly
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            Write-Information 'Install/Import dependent powershell modules...'
            $Module | ForEach-Object {
                if (-not($ImportOnly) -or -not(Get-InstalledModule @_ -AllowPrerelease -EA SilentlyContinue)) {
                    Write-Information "  Install module '$($_.Name)'"
                    Install-Module @_ -Repository PSGallery -AllowPrerelease -Force -Confirm:$false -AllowClobber:$ModuleInstallAllowClobber -EA Stop
                }
                Write-Information "  Import module '$($_.Name)'"
                $_.MinimumVersion = $_.MinimumVersion.Replace('-preview', '')
                Import-Module @_ -EA Stop
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}