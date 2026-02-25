function Set-AzureSqlAADUser {
    <#
      .SYNOPSIS
      Sets Azure SQL user that are authenticated via Azure AD
      
      .DESCRIPTION
      Sets Azure SQL users that are authenticated via Azure AD. The user can be a User, Managed identity or Group 
      in Azure AD

      
      Required permission to run this script: 
      * Azure AD authenticated admin of the Azure SQL being acted on 
      
      .PARAMETER Name
      The name of database user. This needs to correspond to the name of a User or Group in Azure AD
      
      .PARAMETER DatabaseRole
      The list of Azure SQL database roles to assign to the database user
    
      .PARAMETER SqlServerName
      The name of the Azure SQL server. EG my-app-sql   
      
      .PARAMETER DatabaseName
      The name of the Azure SQL server database to add the user to   
      
      .PARAMETER AccessTokenCredential
      The access token, wrapped in a PSCredential, used to authenticate to SQL Server
      
      .EXAMPLE
      $accessToken = Get-AzAccessToken -ResourceUrl https://database.windows.net -AsSecureString -EA Stop
      $accessTokenCreds = [PSCredential]::new("token", $accessToken.Token)
      Set-AzureSqlAADUser 'kc.mriazure_gmail.com#EXT#@kcmriazuregmail.onmicrosoft.com' -SqlServerName my-app-sql -DatabaseName my-app-sql-db -AccessTokenCredential $accessTokenCreds
    
      Description
      -----------
      Ensures there is a datbaase user that is associated with the User in Azure AD

      .EXAMPLE
      Set-AzureSqlAADUser grp-my-app-sql-admin -DatabaseRole db_datareader,db_datawriter -SqlServerName my-app-sql -DatabaseName my-app-sql-db -AccessTokenCredential $accessTokenCreds
    
      Description
      -----------
      Ensures there is a datbaase user that is associated with the Group 'grp-my-app-sql-admin' in Azure AD.
      Ensure this datbaase user is assigned the db_datareader and db_datawriter database roles
      
      .EXAMPLE
      Set-AzureSqlAADUser web-api-identity -SqlServerName my-app-sql -DatabaseName my-app-sql-db -AccessTokenCredential $accessTokenCreds
    
      Description
      -----------
      Ensures there is a datbaase user that is associated with the managed identity named 'web-api-identity'
      
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $Name,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string[]] $DatabaseRole = @(),

        [Parameter(Mandatory)]
        [string] $SqlServerName,
        
        [Parameter(Mandatory)]
        [string] $DatabaseName,

        [Parameter(Mandatory)]
        [PsCredential] $AccessTokenCredential
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        $createUserSqlTemplate = @"
IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name ='{0}') BEGIN
    CREATE USER [{0}] FROM EXTERNAL PROVIDER;
END
"@

        $assignUserRoleSqlTemplate = @"
IF IS_ROLEMEMBER('{0}','{1}') = 0 BEGIN
    ALTER ROLE {0} ADD MEMBER [{1}];
END
"@
    }
    process {
        try {

            $sqlStatements = @(
                $createUserSqlTemplate -f $Name
                $DatabaseRole | ForEach-Object { $assignUserRoleSqlTemplate -f $_, $Name }
            )
            $setDbUserSql = $sqlStatements | Out-String

            $setDbUserParams = @{
                AccessToken         =   $AccessTokenCredential.GetNetworkCredential().Password
                ServerInstance      =   "$SqlServerName.database.windows.net"
                Database            =   $DatabaseName
                Query               =   $setDbUserSql
                # Encrypt=Strict forces TDS 8.0 / TLS 1.3 exclusively, required when Azure SQL enforces
                # minimum TLS 1.3. Without this, Microsoft.Data.SqlClient negotiates TLS 1.2 on Linux.
                # See: https://github.com/dotnet/SqlClient/issues/2546
                Encrypt             =   'Strict'
                ConnectionTimeout   =   60
                QueryTimeout        =   60
            }
            Write-Information "  Executing SQL..."
            Write-Verbose "  SQL: $setDbUserSql"
            Invoke-SqlCmd @setDbUserParams -EA Stop | Out-Null
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}