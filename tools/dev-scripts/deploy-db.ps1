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

        $migrationSqlPath = Join-Path $Path migrate-db.sql

        Write-Information "Running database script against '$SqlServerName/$DatabaseName'..."

        Write-Information "  Acquiring access token using current az account context..."
        $accessToken = Invoke-Exe {
            az account get-access-token --resource https://database.windows.net
        } | ConvertFrom-Json | Select-Object -ExpandProperty accessToken

        $sql = Get-Content $migrationSqlPath -Raw -EA Stop
        $sqlParams = @{
            AccessToken         =   $accessToken
            ServerInstance      =   "$SqlServerName.database.windows.net"
            Database            =   $DatabaseName
            Query               =   $sql
            ConnectionTimeout   =   60
            QueryTimeout        =   120
        }
        Write-Information "  Executing SQL..."
        Write-Verbose "  SQL: $sqlParams"
        try {
            Invoke-SqlCmd @sqlParams -EA Stop | Out-Null
        }
        catch {
            $wait = 60
            Write-Warning "  SQL Script failed... retrying token acquistion after a delay of $wait seconds"
            Start-Sleep -Seconds $wait
            $accessToken = Invoke-Exe {
                az account get-access-token --resource https://database.windows.net
            } | ConvertFrom-Json | Select-Object -ExpandProperty accessToken
            Write-Warning "  Re-executing SQL..."
            Invoke-SqlCmd @sqlParams -AccessToken $accessToken -EA Stop | Out-Null
        }
    }
    catch {
        Write-Error -ErrorRecord $_ -EA $callerEA
    }
}
