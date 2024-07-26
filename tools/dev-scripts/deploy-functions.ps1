<#
    .SYNOPSIS
    Deploys Azure Functions App
    
    .PARAMETER ResourceGroup
    The name of the resource group for the function app    
        
    .PARAMETER Name
    The name of the the function app    
    
    .PARAMETER ConfigureAppSettingsJson
    A script block that will receive the values in appsettings.json as a hashtable. Use this script block
    to update the appsettings.json file that will be deployed to azure functions  
      
    .PARAMETER AppSettings
    Key/Value pairs that will be uploaded to the appsettings of the App service function plan.
    Some settings in Azure functions HAS to be configured using the appsettings of an App service plan. 
    For example app insights instrumentation key.
    For all other settings, probably best to use appsettings.json file so that the settings and
    the function code get deployed atomically at the same time (see ConfigureAppSettingsJson parameter)

#>


[CmdletBinding()]
param(
    [string] $Path = 'out/Template.Functions',
    
    [Parameter(Mandatory)]
    [string] $ResourceGroup,

    [Parameter(Mandatory)]
    [string] $Name,
    
    [ScriptBlock] $ConfigureAppSettingsJson,
    [Hashtable] $AppSettings = @{}
)
begin {
    Set-StrictMode -Version 'Latest'
    $callerEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    
    . "./tools/infrastructure/ps-functions/hashtable-functions.ps1"
    . "./tools/infrastructure/ps-functions/Invoke-Exe.ps1"
    . "./tools/infrastructure/ps-functions/Invoke-ExeExpression.ps1"
    . "./tools/dev-scripts/Set-AppSettings.ps1"
}
process {
    try {
        if ($ConfigureAppSettingsJson) {
            Set-AppSettings $Path $ConfigureAppSettingsJson
        }
        
        $parentPath = Split-Path $Path -Parent
        $folderToZip = Split-Path $Path -Leaf
        $zipArchiveFullPath = Join-Path $parentPath "$folderToZip.zip"
        Remove-Item -Path $zipArchiveFullPath -EA SilentlyContinue
        [System.IO.Compression.ZipFile]::CreateFromDirectory($Path, $zipArchiveFullPath)

        Invoke-Exe {
            az functionapp deployment source config-zip -g $ResourceGroup -n $Name --src $zipArchiveFullPath
        } | Out-Null

        if ($AppSettings.Keys.Count) {
            $appSettingsString = $AppSettings | ConvertTo-StringData | Join-String -Separator ' '
            $updateAppSettings = "az functionapp config appsettings set -n $Name -g $ResourceGroup --settings $appSettingsString"
            Invoke-ExeExpression $updateAppSettings | Out-Null
        }
    }
    catch {
        Write-Error -ErrorRecord $_ -EA $callerEA
    }
}
