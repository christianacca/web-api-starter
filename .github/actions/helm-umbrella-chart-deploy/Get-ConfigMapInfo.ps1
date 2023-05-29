function Get-ConfigMapInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ChartPath,
        [string] $ConfigMaps
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        function Get-PascalCaseString {
            param([string] $Value)

            $parts = $Value -split '-' | ForEach-Object {
                $_.SubString(0, 1).ToUpper() + $_.SubString(1)
            }
            $parts -join '_'
        }
    }
    process {
        try {
            if ($ConfigMaps) {
                $configMapEntries = $ConfigMaps.Trim() -split [System.Environment]::NewLine
                $configMapEntries | ForEach-Object {
                    $keyValue = $_ -split '='
                    $chartName = $keyValue[0].Trim()
                    $settingFilePath= $keyValue[1].Trim()
                    $fullSettingFilePath = Join-Path $ChartPath $settingFilePath
                    
                    if (-not(Test-Path $fullSettingFilePath)) {
                        throw "config map file not found at '$fullSettingFilePath'"
                    }
                    
                    @{
                        Key             =   Get-PascalCaseString $chartName
                        FilePath        =   $fullSettingFilePath
                        FileExtension   =   [System.IO.Path]::GetExtension($settingFilePath)
                    }
                }
            } else {
                @()
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
