function Set-AppSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,
        
        [Parameter(Mandatory)]
        [ScriptBlock] $ConfigureSettings
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            $appSettingsFilePath = Join-Path $Path appsettings.json
            $appSettings = Get-Content $appSettingsFilePath -Raw -EA Stop | ConvertFrom-Json -AsHashtable
            Invoke-Command $ConfigureSettings -ArgumentList $appSettings
            $appSettings | ConvertTo-Json -Depth 100 | Set-Content $appSettingsFilePath
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}