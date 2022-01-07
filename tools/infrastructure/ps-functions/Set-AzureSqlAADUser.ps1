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
      
      .PARAMETER ServicePrincipalCredential
      The credentials of a service principal to sign in to Azure to set the security context used to run the SQL that adds
      database users. This user must be an AAD Admin for the Azure SQL database.
      If not supplied the security context of the current user logged in via Connect-AzAccount will be used
      
      .EXAMPLE
      Set-AzureSqlAADUser 'kc.mriazure_gmail.com#EXT#@kcmriazuregmail.onmicrosoft.com' -SqlServerName my-app-sql -DatabaseName my-app-sql-db
    
      Description
      -----------
      Ensures there is a datbaase user that is associated with the User in Azure AD

      .EXAMPLE
      Set-AzureSqlAADUser grp-my-app-sql-admin -DatabaseRole db_datareader,db_datawriter -SqlServerName my-app-sql -DatabaseName my-app-sql-db
    
      Description
      -----------
      Ensures there is a datbaase user that is associated with the Group 'grp-my-app-sql-admin' in Azure AD.
      Ensure this datbaase user is assigned the db_datareader and db_datawriter database roles
      
      .EXAMPLE
      Set-AzureSqlAADUser web-api-identity -SqlServerName my-app-sql -DatabaseName my-app-sql-db
    
      Description
      -----------
      Ensures there is a datbaase user that is associated with the managed identity named 'web-api-identity'
      
      .EXAMPLE
      $creds = Get-Credential -UserName 96a99e94-acdc-41a0-ae6a-0836b968de57
      Set-AzureSqlAADUser grp-my-app-sql-admin -ServicePrincipalCredential $creds -SqlServerName my-app-sql -DatabaseName my-app-sql-db
    
      Description
      -----------
      Execute the SQL signed in under the credentials of the service principal supplied
      
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

        [PSCredential] $ServicePrincipalCredential
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
        $servicePrincipalAppId = if ($ServicePrincipalCredential) {
            $ServicePrincipalCredential.UserName
        } else {
            $null
        }

        Write-Information "Setting Azure SQL '$SqlServerName/$DatabaseName' database users..."
        
        try {
            $currentAzContext = Get-AzContext -EA Stop
            if (-not($currentAzContext)) {
                throw 'There is no Azure Account context set. Please make sure to login using Connect-AzAccount'
            }

            if ($servicePrincipalAppId) {
                $servicePrincipal = Get-AzADServicePrincipal -ApplicationId $servicePrincipalAppId -EA Stop
                if(-not($servicePrincipal)) {
                    throw "Cannot find a Service Principal object for the supplied ServicePrincipalCredential (searched using AppId: '$servicePrincipalAppId')"
                }
            }

            if ($ServicePrincipalCredential) {
                $connectParams = @{
                    ServicePrincipal    =   $true
                    Credential          =   $ServicePrincipalCredential
                    Tenant              =   $currentAzContext.Tenant.Id
                }
                Write-Information "  Connecting to Azure AD Account using service principal (AppId: '$servicePrincipalAppId')..."
                Connect-AzAccount @connectParams -EA Stop | Out-Null
            }

            $azContextInfo = Get-AzContext -EA Stop |  Select-Object -ExpandProperty Account | Select-Object Id, Type
            Write-Information "  Acquiring access token using current account context ($azContextInfo)..."
            $sqlAdAdminDbToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net -EA Stop).Token
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
    process {
        try {

            $sqlStatements = @(
                $createUserSqlTemplate -f $Name
                $DatabaseRole | ForEach-Object { $assignUserRoleSqlTemplate -f $_, $Name }
            )
            $setDbUserSql = $sqlStatements | Out-String

            $setDbUserParams = @{
                AccessToken         =   $sqlAdAdminDbToken
                ServerInstance      =   "$SqlServerName.database.windows.net"
                Database            =   $DatabaseName
                Query               =   $setDbUserSql
                ConnectionTimeout   =   60
                QueryTimeout        =   60
            }
            Write-Information "  Executing SQL..."
            Write-Verbose "  SQL: $setDbUserSql"
            try {
                Invoke-SqlCmd @setDbUserParams -EA Stop | Out-Null
            }
            catch {
                $wait = 60
                Write-Warning "  SQL Script failed... retrying token acquistion after a delay of $wait seconds"
                Start-Sleep -Seconds $wait
                $sqlAdAdminDbToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net -EA Stop).Token
                Write-Warning "  Re-executing SQL..."
                Invoke-SqlCmd @setDbUserParams -AccessToken $sqlAdAdminDbToken -EA Stop | Out-Null
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
    end {
        if ($ServicePrincipalCredential) {
            Disconnect-AzAccount -EA Continue | Out-Null # restore the original loggin context
        }
    }
}