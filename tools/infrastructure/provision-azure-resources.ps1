    <#
      .SYNOPSIS
      Provision the desired state of the application stack in Azure
      
      .DESCRIPTION
      Provision the desired state of the application stack in Azure. This script is written to be idempotent so it is safe
      to be run multiple times.
      
      This following Azure resources will be provisioned by this script:
      
      * Azure AD groups that will be mapped to Azure SQL database users authenticated by Azure AD
      * Azure AD group membership for the Azure AD SQL Admin group
      * The resource created by ps-functions/Install-FunctionAppAzureResource.ps1
      * The resource created by ps-functions/Install-SqlAzureResource
      
      Required permission to run this script:
      
      * Azure AD 'Groups administrator' role IF the groups do not already exist
      * The permissions required by ps-functions/Install-AppApiAzureResource.ps1
      * The permissions required by ps-functions/Install-SqlAzureResource.ps1
      
    
      .PARAMETER EnvironmentName
      The name of the environment to provision. This value will be used to calculate conventions for that environment.

      .PARAMETER AADSqlAdminServicePrincipalCredential
      The credentials of a service principal to sign in to Azure to set the security context used to run the SQL that adds
      database users. This user must be an AAD Admin for the Azure SQL database (ie a member of the AADSqlAdminGroupName group).
      If not supplied the security context of the current user logged in via Connect-AzAccount will be used.
      Typically you would do this when you want to separate the security permissions for creating Azure resources from
      SQL Admin permissions

      .PARAMETER SkipIncludeCurrentUserInAADSqlAdminGroup
      Skip the default behaviour of adding the current signed in user to the Azure AD group for SQL admins

      .PARAMETER SkipIncludeCurrentUserInAADSqlAdminGroup
      Skip the default behaviour of setting the current IP address as the Azure SQL firewall entry named ProvisioningMachine.
      WARNING: unless the IP address of the machine from which this script is run is whitelisted by the Azure SQL firewall,
      the task this script performs to create database logins will fail

      .PARAMETER Login
      Perform an interactive login to azure

      .PARAMETER SubscriptionId
      The Azure subscription to act on when setting the desired state of Azure resources. If not supplied, then the subscription
      already set as the current context will used (see Get-AzContext, Select-Subscription)

      .PARAMETER ModuleInstallAllowClobber
      Allow the -Clobber switch when installing dependent powershell modules
    
      .EXAMPLE
      ./provision-azure-resources.ps1 -InformationAction Continue
    
      Description
      -----------
      Creates all the Azure resources for the 'dev' environment, displaying to the console details of the task execution.

      .EXAMPLE
      ./provision-azure-resources.ps1 -Login
   
      Description
      -----------
      Trigger an interactive login where you sign in to Azure before creating all the Azure resources using the defaults
    
      .EXAMPLE
      $pswd = ConvertTo-SecureString xxx23234ggg*k -AsPlainText
      ./provision-azure-resources.ps1 -EnvironmentName qa
    
      Description
      -----------
      Creates all the Azure resources for the 'qa' environment
      
      .EXAMPLE
      $creds = Get-Credential -UserName 96a99e94-acdc-41a0-ae6a-0836b968de57
      ./provision-azure-resources.ps1 -AADSqlAdminServicePrincipalCredential $creds
    
      Description
      -----------
      Execute the SQL to create database users signed in under the credentials of the service principal supplied
      
      .EXAMPLE
      ./provision-azure-resources.ps1 -ModuleInstallAllowClobber
    
      Description
      -----------
      Run script supplying ModuleInstallAllowClobber to resolve the error you receive: 
      "The following commands are already available on this system:'Login-AzAccount,...'. This module 'Az.Accounts' may override the existing commands"

      IMPORTANT: this might affect existing scripts written to use commandets from the legacy AzureAD powershell modules
    #>

    
    [CmdletBinding()]
    param(
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',
        
        [PSCredential] $AADSqlAdminServicePrincipalCredential,
        
        [switch] $SkipIncludeCurrentUserInAADSqlAdminGroup,
        [switch] $SkipIncludeCurrentIPAddressInSQLFirewall,
        
        [switch] $Login,

        [string] $SubscriptionId,

        [switch] $ModuleInstallAllowClobber
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        $WarningPreference = 'Continue'

        . "$PSScriptRoot/ps-functions/Get-AppRoleId.ps1"
        . "$PSScriptRoot/ps-functions/Get-ResourceConvention.ps1"
        . "$PSScriptRoot/ps-functions/Grant-ADAppRolePermision.ps1"
        . "$PSScriptRoot/ps-functions/Install-FunctionAppAzureResource.ps1"
        . "$PSScriptRoot/ps-functions/Install-ManagedIdentityAzureResource.ps1"
        . "$PSScriptRoot/ps-functions/Install-SqlAzureResource.ps1"
        . "$PSScriptRoot/ps-functions/Install-ScriptDependency.ps1"
        . "$PSScriptRoot/ps-functions/Set-AADGroup.ps1"
        . "$PSScriptRoot/ps-functions/Set-AzureSqlAADUser.ps1"
        
        $templatePath = Join-Path $PSScriptRoot arm-templates

        $summaryInfo = @{}
        function Add-Summary {
            param([string] $Description, [string] $Value)
            $key = $Description.Replace(' ', '')
            Write-Information "  INFO | $($Description):- $Value"
            $summaryInfo[$key] = $Value
        }
    }
    process {
        try {
            Install-ScriptDependency -Module @(
                @{
                    Name            = 'Az'
                    MinimumVersion  = '7.2.1'
                }
                @{
                    Name            = 'SqlServer'
                    MinimumVersion  = '21.1.18257-preview'
                }
            )

            if ($Login) {
                Write-Information 'Connecting to Azure AD Account...'

                if ($SubscriptionId) {
                    Connect-AzAccount -Subscription $SubscriptionId -EA Stop | Out-Null
                } else {
                    Connect-AzAccount -EA Stop | Out-Null
                }
            } elseif ($SubscriptionId) {
                Select-AzSubscription -SubscriptionId $SubscriptionId -EA Stop | Out-Null
            }
            
            $currentAzContext = Get-AzContext -EA Stop
            if (-not($currentAzContext)) {
                throw 'There is no Azure Account context set. Please make sure to login using Connect-AzAccount'
            }
            
            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable
            $appResourceGroup = $convention.AppResourceGroup

            #------------- Set resource group -------------
            if (-not(Get-AzResourceGroup ($appResourceGroup.ResourceName) -EA SilentlyContinue)) {
                Write-Information "Creating Azure Resource Group '$($appResourceGroup.ResourceName)'..."
                New-AzResourceGroup ($appResourceGroup.ResourceName) ($appResourceGroup.ResourceLocation) -EA Stop | Out-Null
            }

            
            #------------- Set user assigned managed identity for api -------------
            $api = $convention.SubProducts.Api
            $apiManagedIdArmParams = @{
                ResourceGroup           =   $appResourceGroup.ResourceName
                Name                    =   $api.ManagedIdentity
                TemplateFile            =   Join-Path $templatePath api-managed-identity.json
            }
            $apiManagedId = Install-ManagedIdentityAzureResource @apiManagedIdArmParams -EA Stop
            Add-Summary 'Api Managed Identity Client Id' ($apiManagedId.ClientId)


            #------- Set Azure function app resource --------
            $funcApp = $convention.SubProducts.Func
            $appOnlyAppRoleName = 'app_only'
            $funcAppParams = @{
                ResourceGroup           =   $appResourceGroup.ResourceName
                Name                    =   $funcApp.ResourceName
                ManagedIdentityName     =   $funcApp.ManagedIdentity
                AppRoleDisplayName      =   $appOnlyAppRoleName
                TemplateDirectory       =   $templatePath
            }
            $funcAppInfo = Install-FunctionAppAzureResource @funcAppParams


            #------------- Assign AD app role for function app to api managed identity -------------
            $appRoleGrants = [PSCustomObject]@{
                TargetAppDisplayName                =   $funcApp.ResourceName
                AppRoleId                           =   Get-AppRoleId $appOnlyAppRoleName ($funcApp.ResourceName)
                ManagedIdentityDisplayName          =   $api.ManagedIdentity
                ManagedIdentityResourceGroupName    =   $appResourceGroup.ResourceName
            }
            $appRoleGrants | Grant-ADAppRolePermision


            #------- Set Azure AD SQL Groups and membership --------
            $dbCrudMembership = @(
                @{
                    ApplicationId       =   $summaryInfo.ApiManagedIdentityClientId
                    Type                =   'ServicePrincipal'
                }
                @{
                    ApplicationId       =   $funcAppInfo.FunctionAppManagedIdentityClientId
                    Type                =   'ServicePrincipal'
                }
            )
            $sqlServer = $convention.SubProducts.Sql
            $sqlDatabase = $convention.SubProducts.Db
            $groups = @(
                [PsCustomObject]@{
                    Name                =   $sqlServer.ADAdminGroupName
                    IncludeCurrentUser  =   -not($SkipIncludeCurrentUserInAADSqlAdminGroup)
                }
                $sqlDatabase.DatabaseGroupUser | ForEach-Object { 
                    [PsCustomObject]@{ 
                        Name    = $_.Name
                        Member  = if ($_.Name -like '*.Crud') { $dbCrudMembership } else { @() }
                    }  
                }
            )
            $groups | Set-AADGroup


            #------- Set Azure SQL --------
            $secondarySqlServerName = if ($sqlServer.Failover) { $sqlServer.Failover.ResourceName } else { $null }
            $secondarySqlServerLocation = if ($sqlServer.Failover) { $sqlServer.Failover.ResourceLocation } else { $null }
            $sqlParams = @{
                ResourceGroup                               =   $convention.DataResourceGroup.ResourceName
                ResourceLocation                            =   $convention.DataResourceGroup.ResourceLocation
                TemplateDirectory                           =   $templatePath
                SqlServerName                               =   $sqlServer.Primary.ResourceName
                SecondarySqlServerName                      =   $secondarySqlServerName
                SecondarySqlServerLocation                  =   $secondarySqlServerLocation
                DatabaseName                                =   $sqlDatabase.ResourceName
                ManagedIdentityName                         =   $sqlServer.ManagedIdentity
                AADSqlAdminGroupName                        =   $sqlServer.ADAdminGroupName
                FirewallRule                                =   $sqlServer.Firewall.Rule
                AllowAllAzureServices                       =   $sqlServer.Firewall.AllowAllAzureServices
                SkipIncludeCurrentIPAddressInSQLFirewall    =   $SkipIncludeCurrentIPAddressInSQLFirewall
            }
            $sqlInfo = Install-SqlAzureResource @sqlParams


            #------- Set Azure SQL users --------
            $dbUsers = $sqlDatabase.DatabaseGroupUser | ForEach-Object { [PsCustomObject]$_ }
            $dbConnectionParams = @{
                SqlServerName               =   $sqlServer.Primary.ResourceName
                DatabaseName                =   $sqlDatabase.ResourceName
                ServicePrincipalCredential  =   $AADSqlAdminServicePrincipalCredential
            }
            $dbUsers | Set-AzureSqlAADUser @dbConnectionParams


            $summary = $funcAppInfo + $summaryInfo + $sqlInfo
            Write-Host '******************* Summary: start ******************************'
            $summary.Keys | ForEach-Object {
                Write-Host "$($_): $($summary[$_])" -ForegroundColor Yellow
            }
            Write-Host '******************* Summary: end ********************************'

            $summary
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
