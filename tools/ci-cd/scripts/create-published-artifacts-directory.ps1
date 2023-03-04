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
        $helmChartDetinationPath = Join-Path $Destination helm-chart
    }
    process {
        try {
            Remove-Item $Destination -Confirm:$false -Recurse -Force -EA SilentlyContinue
            New-Item $Destination -ItemType Container -Force | Out-Null
            Copy-Item (Join-Path $BuildArtifactsPath migrate-db.sql) $Destination
            Copy-Item tools/ci-cd/helm-chart $helmChartDetinationPath -Recurse
            Get-ChildItem $BuildArtifactsPath/* -Include appsettings.json -Recurse |
                Where-Object { Get-ChildItem $_.PSParentPath -Filter 'Dockerfile' } |
                ForEach-Object {
                    $dest = Join-Path $helmChartDetinationPath $_.FullName.SubString($buildArtifactsFullPath.Length)
                    # Copy-Item won't create the folder structure; solution: create a blank file and then overwrite it
                    New-Item $dest -Type File -Force | Out-Null
                    Copy-Item $_.FullName -Destination $dest -Force
                }
            Get-ChildItem $BuildArtifactsPath/* -Directory  |
                Where-Object { Get-ChildItem $_ -Filter 'host.json' } |
                ForEach-Object { Copy-Item $_.FullName $Destination -Recurse }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }