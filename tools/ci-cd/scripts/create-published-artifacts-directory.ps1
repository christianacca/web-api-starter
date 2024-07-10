    [CmdletBinding()]
    param(
        [string] $Destination = 'out',
        [string] $BuildArtifactsPath = 'publish'
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        $buildArtifactsFullPath = Resolve-Path $BuildArtifactsPath | Select-Object -ExpandProperty Path
    }
    process {
        try {
            Remove-Item $Destination -Confirm:$false -Recurse -Force -EA SilentlyContinue
            New-Item $Destination -ItemType Container -Force | Out-Null
            Copy-Item (Join-Path $BuildArtifactsPath migrate-db.sql) $Destination
            # copy function apps to the destination directory
            Get-ChildItem $BuildArtifactsPath/* -Directory  |
                Where-Object { Get-ChildItem $_ -Filter 'host.json' } |
                ForEach-Object { Copy-Item $_.FullName $Destination -Recurse }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }