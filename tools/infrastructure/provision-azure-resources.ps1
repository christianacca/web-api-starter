    <#
      .SYNOPSIS
      Provision the desired state of the application stack in Azure
      
      .DESCRIPTION
      Provision the desired state of the application stack in Azure. This script is written to be idempotent so it is safe
      to be run multiple times.
      
      This following Azure resources will be provisioned by this script:
      
      * User assgined managed identity that are bound to pod(s) running in AKS (one managed identity per AKS service)
      * Azure Function app x2 ('internalapi', 'testpbi')
      * User assigned managed identity assigned as the identity for Azure function apps
      * Azure AD App registration and associated AD Enterprise app (aka service principal). This App registration is associated with the 
        Azure Function app 'internalapi' to authentication requests from the AKS pods
      * Azure SQL database (logical server and single database for a primary and failover region) configured with:
        - Azure AD authentication
        - Azure AD Admin mapped to an Azure AD group
        - Contained database users mapped to the Azure AD groups
      * User assigned managed identity assigned as the identity for Azure SQL Server    
      * Azure AD groups that will be mapped to Azure SQL database users authenticated by Azure AD
      * Azure AD groups that will be used to assign permissions to power-bi workspaces to the api and function app
      * Azure AD group membership for the above AD groups
      
      Required permission to run this script as a service principal:
      
      * Azure RBAC Role: 'Azure Contributor' and 'User Access Administrator'
      * Azure AD role: 'Application developer'
      * Azure AD permission: 'microsoft.directory/groups.security/createAsOwner' (or member of 'sg.aad.role.custom.securitygroupcreator' Azure AD group)
      * MS Graph API permission: 'Application.ReadWrite.OwnedBy'
      * Owner of Azure AD group 'sg.aad.role.custom.azuresqlauthentication'
        (assumed that 'sg.aad.role.custom.azuresqlauthentication' has been assigned MS Graph directory permissions
        as described here: https://docs.microsoft.com/en-us/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity?view=azuresql#permissions)
    
      Required permission to run this script as a user:
      
      * Azure RBAC Role: 'Azure Contributor' and 'User Access Administrator'
      * Azure AD role: 'Application administrator'
      * Azure AD permission: 'microsoft.directory/groups.security/createAsOwner' (or member of 'sg.aad.role.custom.securitygroupcreator' Azure AD group)
      * Owner of Azure AD group 'sg.aad.role.custom.azuresqlauthentication'
        (assumed that 'sg.aad.role.custom.azuresqlauthentication' has been assigned MS Graph directory permissions
        as described here: https://docs.microsoft.com/en-us/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity?view=azuresql#permissions)
    
    
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

      .PARAMETER SkipIncludeCurrentIPAddressInSQLFirewall
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
    
      .PARAMETER InstallModulesOnly
      Only install powershell modules that this script depends on. Do NOT actually provision infrastructure
        
      .PARAMETER ListModuleRequirementsOnly
      Return the list of powershell modules that this script depends on. Do NOT actually provision infrastructure
            
      .PARAMETER SkipInstallModules
      Do NOT install powershell modules that this script depends on. Assumes that these modules are already installed
    
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

        [switch] $ModuleInstallAllowClobber,
        [switch] $InstallModulesOnly,
        [switch] $ListModuleRequirementsOnly,
        [switch] $SkipInstallModules
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        $WarningPreference = 'Continue'

        . "$PSScriptRoot/ps-functions/Get-AppRoleId.ps1"
        . "$PSScriptRoot/ps-functions/Get-AzModuleInfo.ps1"
        . "$PSScriptRoot/ps-functions/Get-CurrentUserAsMember.ps1"
        . "$PSScriptRoot/ps-functions/Get-RbacRoleAssignment.ps1"
        . "$PSScriptRoot/ps-functions/Get-ScriptDependencyList.ps1"
        . "$PSScriptRoot/ps-functions/Grant-ADAppRolePermission.ps1"
        . "$PSScriptRoot/ps-functions/Grant-RbacRole.ps1"
        . "$PSScriptRoot/ps-functions/Invoke-Exe.ps1"
        . "$PSScriptRoot/ps-functions/Install-FunctionAppAzureResource.ps1"
        . "$PSScriptRoot/ps-functions/Install-ManagedIdentityAzureResource.ps1"
        . "$PSScriptRoot/ps-functions/Install-SqlAzureResource.ps1"
        . "$PSScriptRoot/ps-functions/Install-ScriptDependency.ps1"
        . "$PSScriptRoot/ps-functions/Install-TrafficManagerProfileResource.ps1"
        . "$PSScriptRoot/ps-functions/Resolve-RbacRoleAssignment.ps1"
        . "$PSScriptRoot/ps-functions/Set-ADAppCredential.ps1"
        . "$PSScriptRoot/ps-functions/Set-ADApplication.ps1"
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

        function Get-PrefixedSummary {
            param([Hashtable] $Summary, [string] $Prefix)
            $result = @{}
            $summary.Keys | ForEach-Object {
                $result["$($Prefix)$($_)"] = $summary[$_]
            }
            $result
        }
    }
    process {
        try {
            $modules = @(
                Get-AzModuleInfo
                @{
                    Name            = 'SqlServer'
                    MinimumVersion  = '22.0.59'
                }
            )
            if ($ListModuleRequirementsOnly) {
                Get-ScriptDependencyList -Module $modules
                return
            } else {
                Install-ScriptDependency -ImportOnly:$SkipInstallModules -Module $modules
            }
            
            if ($InstallModulesOnly) {
                return
            }

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
            
            
            #------------- Team AAD groups -------------
            $teamGroups = $convention.Ad.AadSecurityGroup | ForEach-Object { [PsCustomObject]$_ }
            $teamGroups | Set-AADGroup
            

            #------------- Set resource group -------------
            $rg = Get-AzResourceGroup ($appResourceGroup.ResourceName) -EA SilentlyContinue
            if (-not($rg)) {
                Write-Information "Creating Azure Resource Group '$($appResourceGroup.ResourceName)'..."
                $rg = New-AzResourceGroup ($appResourceGroup.ResourceName) ($appResourceGroup.ResourceLocation) -EA Stop
            }

            
            #------- Set Azure RBAC --------
            Write-Information "Assigning RBAC roles to scope '$($rg.ResourceId)'..."
            $currentUserMember = Get-CurrentUserAsMember
            $kvSecretOfficer = $convention.SubProducts.KeyVault.RbacAssignment | Where-Object Role -eq 'Key Vault Secrets Officer'
            $kvSecretOfficer.Member = @($currentUserMember; $kvSecretOfficer.Member)
            $roleAssignments = Get-RbacRoleAssignment $convention
            $roleAssignments | Resolve-RbacRoleAssignment | Grant-RbacRole -Scope $rg.ResourceId
            Write-Information 'RBAC permissions granted (see table below)'
            $roleAssignments | Format-Table

            
            #------------- Create key vault -------------
            $keyvault = $convention.SubProducts.KeyVault
            Write-Information "Setting Azure Key Vault '$($keyvault.ResourceName)'..."
            $keyvaultParams = @{
                ResourceGroupName       =   $appResourceGroup.ResourceName
                TemplateParameterObject =   @{
                    keyVaultName            =   $keyVault.ResourceName
                    enablePurgeProtection   =   $keyVault.EnablePurgeProtection
                }
                TemplateFile            =   Join-Path $templatePath key-vault.bicep
            }
            New-AzResourceGroupDeployment @keyvaultParams -EA Stop | Out-Null


            #------------- Azure monitor (eg app insights) -------------
            Write-Information "Setting Azure monitor resources..."
            $appInsights = $convention.SubProducts.AppInsights
            $monitorArmParams = @{
                ResourceGroupName       =   $appInsights.ResourceGroupName
                TemplateParameterObject =   @{
                    alertEmailCritical      =   $convention.IsEnvironmentProdLike ? 'christian.crowhurst@gmail.com' : 'christian.crowhurst@gmail.com'
                    alertEmailNonCritical   =   $convention.IsEnvironmentProdLike ? 'christian.crowhurst@gmail.com' : 'christian.crowhurst@gmail.com'
                    appInsightsName         =   $appInsights.ResourceName
                    appName                 =   $convention.ProductName
                    enableMetricAlerts      =   $appInsights.IsMetricAlertsEnabled
                    environmentName         =   $EnvironmentName
                    environmentAbbreviation =   $appInsights.EnvironmentAbbreviation
                    workspaceName           =   $appInsights.WorkspaceName
                }
                TemplateFile            =   Join-Path $templatePath azure-monitor.bicep
            }
            $monitoringOutput = New-AzResourceGroupDeployment @monitorArmParams -EA Stop | ForEach-Object { $_.Outputs }
            
            #------------- Set user assigned managed identity for api -------------
            $api = $convention.SubProducts.Api
            $aksPrimary = $convention.Aks.Primary
            $aksFailoverInfo = $convention.Aks.Failover ? @{
                aksFailoverCluster              =   $convention.Aks.Failover.ResourceName
                aksFailoverClusterResourceGroup =   $convention.Aks.Failover.ResourceGroupName
            } : @{}
            $apiManagedIdArmParams = @{
                ResourceGroup           =   $appResourceGroup.ResourceName
                Name                    =   $api.ManagedIdentity
                TemplateFile            =   Join-Path $templatePath api-managed-identity.bicep
                TemplateParameterObject =   @{
                    aksCluster                      =   $aksPrimary.ResourceName
                    aksClusterResourceGroup         =   $aksPrimary.ResourceGroupName
                    aksServiceAccountName           =   $api.ServiceAccountName
                    aksServiceAccountNamespace      =   $convention.Aks.Namespace
                } + $aksFailoverInfo
            }
            $apiManagedId = Install-ManagedIdentityAzureResource @apiManagedIdArmParams -EA Stop
            Add-Summary 'Api Managed Identity Client Id' ($apiManagedId.ClientId)

            #------------- Set storage accounts -------------
            $reportStorage = $convention.SubProducts.PbiReportStorage
            Write-Information "Setting Report storage account '$($reportStorage.StorageAccountName)'..."
            $storageAccountArmParams = @{
                ResourceGroupName       =   $appResourceGroup.ResourceName
                TemplateParameterObject =   @{
                    storageAccountName      =   $reportStorage.StorageAccountName
                    storageAccountType      =   $reportStorage.StorageAccountType
                    defaultStorageTier      =   $reportStorage.DefaultStorageTier
                }
                TemplateFile            =   Join-Path $templatePath storage-account.bicep
            }
            New-AzResourceGroupDeployment @storageAccountArmParams -EA Stop | Out-Null
            

            #------- Api Traffic manager profile --------
            $apiTmParams = @{
                ResourceGroup       =   $appResourceGroup.ResourceName
                InputObject         =   $convention.SubProducts.ApiTrafficManager
                TemplateDirectory   =   $templatePath
            }
            Install-TrafficManagerProfileResource @apiTmParams -EA Stop | Out-Null


            #------- Web Traffic manager profile --------
            $webTmParams = @{
                ResourceGroup       =   $appResourceGroup.ResourceName
                InputObject         =   $convention.SubProducts.WebTrafficManager
                TemplateDirectory   =   $templatePath
            }
            Install-TrafficManagerProfileResource @webTmParams -EA Stop | Out-Null


            #------- Set Azure function app resource --------
            $funcApp = $convention.SubProducts.InternalApi
            $appOnlyAppRoleName = 'app_only'
            $funcAppParams = @{
                ResourceGroup               =   $appResourceGroup.ResourceName
                Name                        =   $funcApp.ResourceName
                ManagedIdentityName         =   $funcApp.ManagedIdentity
                ManagedIdentityTemplateFile =   'internalapi-managed-identity.bicep'
                AppRoleDisplayName          =   $appOnlyAppRoleName
                TemplateDirectory           =   $templatePath
                TemplateParameterObject     =   @{
                    appInsightsCloudRoleName            =   'Web API Starter Functions'
                    appInsightsConnectionString         =   $monitoringOutput.appInsightsConnectionString.Value
                    deployDefaultStorageQueue           =   $true
                }
                StorageAccountName      =   $funcApp.StorageAccountName
            }
            $funcAppInfo = Install-FunctionAppAzureResource @funcAppParams


            #------------- Assign AD app role for function app to api managed identity -------------
            $appRoleGrants = [PSCustomObject]@{
                TargetAppDisplayName                =   $funcApp.ResourceName
                AppRoleId                           =   Get-AppRoleId $appOnlyAppRoleName ($funcApp.ResourceName)
                ManagedIdentityDisplayName          =   $api.ManagedIdentity
                ManagedIdentityResourceGroupName    =   $appResourceGroup.ResourceName
            }
            $appRoleGrants | Grant-ADAppRolePermission


            #------- Set Azure AD Groups and membership --------
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
            
            $sqlGroups = $sqlDatabase.AadSecurityGroup | ForEach-Object { [PsCustomObject]$_ }
            if (-not($SkipIncludeCurrentUserInAADSqlAdminGroup)) {
                $sqlGroups |
                    Where-Object Name -eq ($sqlServer.AadAdminGroupName) |
                    Add-Member -MemberType NoteProperty -Name IncludeCurrentUser -Value $true
            }
            $sqlGroups |
                Where-Object Name -like '*.crud' |
                ForEach-Object { $_.Member = $dbCrudMembership + $_.Member }
            
            $groups = @($sqlGroups)
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
                AADSqlAdminGroupName                        =   $sqlServer.AadAdminGroupName
                FirewallRule                                =   $sqlServer.Firewall.Rule
                AllowAllAzureServices                       =   $sqlServer.Firewall.AllowAllAzureServices
                SkipIncludeCurrentIPAddressInSQLFirewall    =   $SkipIncludeCurrentIPAddressInSQLFirewall
            }
            $sqlInfo = Install-SqlAzureResource @sqlParams


            #------- Set Azure SQL users --------
            $dbUsers = $sqlDatabase.AadSecurityGroup | ForEach-Object { [PsCustomObject]$_ }
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
