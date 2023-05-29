[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ChartPath,
    
    [string] $ConfigMaps,
    
    [string] $Values,
    
    [string] $AppVersion
)
begin {
    Set-StrictMode -Version 'Latest'
    $callerEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    
    . "$PSScriptRoot/Get-ConfigMapInfo.ps1"
}
process {
    try {
        $configMapInfos = Get-ConfigMapInfo $ChartPath -ConfigMaps $ConfigMaps

        $structuredFileTransformPaths = $configMapInfos |
                Where-Object FileExtension -in '.json', '.yml', '.yaml' |
                Select-Object -Exp FilePath
        ('structuredFileTransformPaths={0}' -f ($structuredFileTransformPaths -join ',')) >> $Env:GITHUB_OUTPUT

        $simpleFileTransformPaths = $configMapInfos | Select-Object -Exp FilePath
        ('simpleFileTransformPaths={0}' -f ($simpleFileTransformPaths -join ',')) >> $Env:GITHUB_OUTPUT

        $valueArgs = if ($Values) {
            $Values.Trim() -split [System.Environment]::NewLine | ForEach-Object { "--set $_" }
        } else {
            ''
        }
        ('helmSetArgs={0}' -f ($valueArgs -join ' ')) >> $Env:GITHUB_OUTPUT

        $chartValuesPath = if(Test-Path (Join-Path $ChartPath values.yml)) {
            Join-Path $ChartPath values.yml
        } else {
            Join-Path $ChartPath values.yaml
        }
        "helmValuesPath=$chartValuesPath" >> $Env:GITHUB_OUTPUT

        $chartYaml = Get-Content (Join-Path $ChartPath Chart.yaml) | ForEach-Object { $_.Replace(':', '=') } | ConvertFrom-StringData
        $chartVersion = $chartYaml | Where-Object { $_['version'] } | Select-Object -First 1 -Exp version
        $chartName = $chartYaml | Where-Object { $_['name'] } | Select-Object -First 1 -Exp name
        $chartPackagePath = Join-Path $ChartPath "$chartName-$chartVersion.tgz"
        "chartPackagePath=$chartPackagePath" >> $Env:GITHUB_OUTPUT
        
        if (!$AppVersion) {
            $AppVersion = $chartYaml | Where-Object { $_['appVersion'] } | Select-Object -First 1 -Exp appVersion    
        }
        "appVersion=$appVersion" >> $Env:GITHUB_OUTPUT
    }
    catch {
        Write-Error -ErrorRecord $_ -EA $callerEA
    }
}
