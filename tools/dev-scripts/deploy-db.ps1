<#
    .SYNOPSIS
    Deploys SQL database migration script
      
#>

[CmdletBinding()]
param(
    [string] $Path = 'out',
    
    [Parameter(Mandatory)]
    [string] $SqlServerName,

    [Parameter(Mandatory)]
    [string] $DatabaseName
)
begin {
    Set-StrictMode -Version 'Latest'
    $callerEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    
    . "./tools/infrastructure/ps-functions/Invoke-Exe.ps1"
    . "./tools/infrastructure/ps-functions/Install-ScriptDependency.ps1"
    
}
process {
    try {
        Install-ScriptDependency -Module @(
            @{
                Name            = 'SqlServer'
                MinimumVersion  = '21.1.18257-preview'
            }
        )

        Write-Information "Running database migrations against '$SqlServerName/$DatabaseName'..."

        Write-Information "  Acquiring access token using current az account context..."
        $accessToken = Invoke-Exe {
            az account get-access-token --resource https://database.windows.net
        } | ConvertFrom-Json | Select-Object -ExpandProperty accessToken
        
        $sql = Get-Content (Join-Path $Path migrate-db.sql) -Raw -EA Stop
        $sqlParams = @{
            AccessToken         =   $accessToken
            ServerInstance      =   "$SqlServerName.database.windows.net"
            Database            =   $DatabaseName
            Query               =   $sql
            ConnectionTimeout   =   60
            QueryTimeout        =   120
        }
        Write-Information "  Executing SQL..."
        Invoke-SqlCmd @sqlParams -EA Stop | Out-Null
    }
    catch {
        Write-Error -ErrorRecord $_ -EA $callerEA
    }
}
