<#
    .SYNOPSIS
    Deploys Azure SQL database script
      
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,
    
    [Parameter(Mandatory)]
    [string] $SqlServerName,

    [Parameter(Mandatory)]
    [string] $DatabaseName
)
begin {
    Set-StrictMode -Version 'Latest'
    $callerEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    
    . "$PSScriptRoot/Invoke-Exe.ps1"
}
process {
    try {
        Write-Information "Running database script against '$SqlServerName/$DatabaseName'..."

        Write-Information "  Acquiring access token using current az account context..."
        $accessToken = Invoke-Exe {
            az account get-access-token --resource https://database.windows.net
        } | ConvertFrom-Json | Select-Object -ExpandProperty accessToken
        
        $sql = Get-Content $Path -Raw -EA Stop
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
