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
      
      * Azure RBAC Role: 'Azure Contributor' and 'User Access Administrator' on
        - resource group for which Azure resource will be created OR
        - subscription IF the resource group does not already exist
      * Azure AD role: 'Application developer'
      * Azure AD permission: 'microsoft.directory/groups.security/createAsOwner' (or member of 'sg.aad.role.custom.securitygroupcreator' Azure AD group)
      * MS Graph API permission: 'Application.ReadWrite.OwnedBy'
      * Owner of Azure AD group 'sg.aad.role.custom.azuresqlauthentication'
        (assumed that 'sg.aad.role.custom.azuresqlauthentication' has been assigned MS Graph directory permissions
        as described here: https://docs.microsoft.com/en-us/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity?view=azuresql#permissions)
    
      Required permission to run this script as a user:
      
      * Azure RBAC Role: 'Azure Contributor' and 'User Access Administrator' on
        - resource group for which Azure resource will be created OR
        - subscription IF the resource group does not already exist
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

      .PARAMETER WhatIfAzureResourceDeployment
      Print resource changes that would be made to Azure but do NOT actually make the changes

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
        [switch] $WhatIfAzureResourceDeployment,
        
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
        . "$PSScriptRoot/ps-functions/Get-ServicePrincipalAccessToken.ps1"
        . "$PSScriptRoot/ps-functions/Grant-ADAppRolePermission.ps1"
        . "$PSScriptRoot/ps-functions/Grant-RbacRole.ps1"
        . "$PSScriptRoot/ps-functions/Invoke-Exe.ps1"
        . "$PSScriptRoot/ps-functions/Install-ScriptDependency.ps1"
        . "$PSScriptRoot/ps-functions/Resolve-RbacRoleAssignment.ps1"
        . "$PSScriptRoot/ps-functions/Set-ADApplication.ps1"
        . "$PSScriptRoot/ps-functions/Set-AADGroup.ps1"
        . "$PSScriptRoot/ps-functions/Set-AzureSqlAADUser.ps1"
        
        $templatePath = Join-Path $PSScriptRoot arm-templates
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

            #-----------------------------------------------------------------------------------------------
            Write-Information '1. Check resource providers are registered...'
            $resourceProviderName = @(
                'Microsoft.Web' # for Azure Function App
            )
            $unregisteredResoureProvider = Get-AzResourceProvider -ListAvailable -EA Stop |
                Where-Object ProviderNamespace -in $resourceProviderName |
                Where-Object RegistrationState -eq 'NotRegistered'
            if ($unregisteredResoureProvider) {
                Write-Information '  Registering resource providers required to run ARM/bicep template...'
                $unregisteredResoureProvider | ForEach-Object {
                    Register-AzResourceProvider -ProviderNamespace $_.ProviderNamespace -EA Stop | Out-Null
                }
            }

            #-----------------------------------------------------------------------------------------------
            Write-Information '2. Acquire Azure resource access tokens...'
            
            # IMPORTANT: we're acquiring the access token here before anything else runs to avoid the risk of
            # any federated id token (eg github id token) having a short expiry and causing access token
            # acquisition to fail when trying to swap the id token for an access token
            $sqlTokenResourceUrl = 'https://database.windows.net'
            $sqlAccessToken = if ($AADSqlAdminServicePrincipalCredential) {
                Get-ServicePrincipalAccessToken $AADSqlAdminServicePrincipalCredential $sqlTokenResourceUrl -EA Stop
            } else {
                Write-Information "Acquiring access token for $sqlTokenResourceUrl using current signed in context..."
                Get-AzAccessToken -ResourceUrl $sqlTokenResourceUrl -EA Stop
            }
            Write-Information "  INFO | Token ExpiresOn: $($sqlAccessToken.ExpiresOn)"
            Write-Information "  INFO | Token TenantId: $($sqlAccessToken.TenantId)"
            Write-Information "  INFO | Token UserId: $($sqlAccessToken.UserId)"
            $sqlAccessTokenString = $sqlAccessToken.Token


            #-----------------------------------------------------------------------------------------------
            Write-Information '3. Set resource group...'
            $appResourceGroup = $convention.AppResourceGroup
            $rg = Get-AzResourceGroup ($appResourceGroup.ResourceName) -EA SilentlyContinue
            if (-not($rg)) {
                Write-Information "Creating Azure Resource Group '$($appResourceGroup.ResourceName)'..."
                $rg = New-AzResourceGroup ($appResourceGroup.ResourceName) ($appResourceGroup.ResourceLocation) -EA Stop
            }


            #-----------------------------------------------------------------------------------------------
            Write-Information '4. Set AAD groups - for Teams...'
            $teamGroups = $convention.Ad.AadSecurityGroup | ForEach-Object { [PsCustomObject]$_ }
            $teamGroups | Set-AADGroup | Out-Null


            #-----------------------------------------------------------------------------------------------
            Write-Information "5. Set Azure RBAC - for teams to scope '$($rg.ResourceId)'..."
            $currentUserMember = Get-CurrentUserAsMember
            $kvSecretOfficer = $convention.SubProducts.KeyVault.RbacAssignment | Where-Object Role -eq 'Key Vault Secrets Officer'
            $kvSecretOfficer.Member = @($currentUserMember; $kvSecretOfficer.Member)
            $roleAssignments = Get-RbacRoleAssignment $convention
            $roleAssignments | Resolve-RbacRoleAssignment | Grant-RbacRole -Scope $rg.ResourceId
            Write-Information 'RBAC permissions granted (see table below)'
            $roleAssignments | Format-Table


            #-----------------------------------------------------------------------------------------------
            Write-Information '6. Set AAD groups - for Azure resource (pre-resource creation)...'
            $sqlAdAdminGroup = Set-AADGroup $convention.SubProducts.Sql.AadAdminGroupName -EA Stop


            #-----------------------------------------------------------------------------------------------
            Write-Information '7. Set AAD App registrations...'
            $funcApiName = $convention.SubProducts.InternalApi.ResourceName
            $appOnlyAppRoleName = 'app_only'
            $funcAdParams = @{
                IdentifierUri       =   "api://$funcApiName"
                DisplayName         =   $funcApiName
                AppRole             =   @{
                    Id                  =   Get-AppRoleId $appOnlyAppRoleName $funcApiName
                    AllowedMemberType   =   'Application'
                    DisplayName         =   $appOnlyAppRoleName
                    Description         =   'Service-to-Service access'
                    Value               =   'app_only_access'
                    IsEnabled           =   $true
                }
            }
            $funcAdRegistration = Set-ADApplication -InputObject $funcAdParams


            #-----------------------------------------------------------------------------------------------
            Write-Information '8. Set Azure resources...'
            $currentIpRule = if (-not($SkipIncludeCurrentIPAddressInSQLFirewall)) {
                $currentIPAddress = ((Invoke-WebRequest -Uri https://icanhazip.com).Content).Trim()
                @{
                    StartIpAddress  =   $currentIPAddress
                    EndIpAddress    =   $currentIPAddress
                    Name            =   'ProvisioningMachine'
                }
            } else {
                @()
            }
            if ($convention.SubProducts.Sql.Firewall.Rule) {
                $convention.SubProducts.Sql.Firewall.Rule = @($convention.SubProducts.Sql.Firewall.Rule; $currentIpRule)    
            }
            $mainArmParams = @{
                ResourceGroupName       =   $appResourceGroup.ResourceName
                TemplateParameterObject =   @{
                    internalApiClientId         =   $funcAdRegistration.AppId
                    settings                    =   $convention
                    sqlAdAdminGroupObjectId     =   $sqlAdAdminGroup.Id
                }
                TemplateFile        =   Join-Path $templatePath main.bicep
            }
            if ($WhatIfAzureResourceDeployment) {
                Write-Information '  Print Azure resource desired state changes only...'
                New-AzResourceGroupDeployment @mainArmParams -WhatIf -WhatIfExcludeChangeType Ignore, NoChange, Unsupported -EA Stop
                return
            }
            $armResources = New-AzResourceGroupDeployment @mainArmParams -EA Stop | ForEach-Object { $_.Outputs }
            Write-Information "  INFO | Api Managed Identity Client Id:- $($armResources.apiManagedIdentityClientId.Value)"
            Write-Information "  INFO | Internal Api Managed Identity Client Id:- $($armResources.internalApiManagedIdentityClientId.Value)"
            Write-Information "  INFO | 'Azure SQL Managed Identity Client Id':- $($armResources.sqlManagedIdentityClientId.Value)"


            #-----------------------------------------------------------------------------------------------
            Write-Information '9. Set AAD App role memberships...'
            
            # 8.1. Set AD app role for function app to api managed identity
            $funcApp = $convention.SubProducts.InternalApi
            $appRoleGrants = [PSCustomObject]@{
                TargetAppDisplayName                =   $funcApp.ResourceName
                AppRoleId                           =   Get-AppRoleId $appOnlyAppRoleName ($funcApp.ResourceName)
                ManagedIdentityDisplayName          =   $convention.SubProducts.Api.ManagedIdentity
                ManagedIdentityResourceGroupName    =   $appResourceGroup.ResourceName
            }
            $appRoleGrants | Grant-ADAppRolePermission


            #-----------------------------------------------------------------------------------------------
            Write-Information '10. Set AAD groups - for resources (post-resource creation)...'
            
            $wait = 15
            Write-Information "Waitinng $wait secconds for new identities and/or groups to be propogated before assigning group membership"
            Start-Sleep -Seconds $wait

            # assign delgated RBAC permissions to sql server managed identity to authenticate sql users against Azure AD
            $sqlAadAuthGroup = [PsCustomObject]@{
                Name                =   'sg.aad.role.custom.azuresqlauthentication'
                Member              = @{
                    ApplicationId       =   $armResources.sqlManagedIdentityClientId.Value
                    Type                =   'ServicePrincipal'
                }
            }
            
            $dbCrudMembership = @(
                @{
                    ApplicationId       =   $armResources.apiManagedIdentityClientId.Value
                    Type                =   'ServicePrincipal'
                }
                @{
                    ApplicationId       =   $armResources.internalApiManagedIdentityClientId.Value
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

            $groups = @($sqlGroups; $sqlAadAuthGroup)
            $groups | Set-AADGroup | Out-Null


            #-----------------------------------------------------------------------------------------------
            Write-Information '11. Set Data plane operations...'

            # Azure SQL users
            Write-Information 'Setting Azure SQL users logins...'
            $dbUsers = $sqlDatabase.AadSecurityGroup | ForEach-Object { [PsCustomObject]$_ }
            $dbConnectionParams = @{
                SqlServerName               =   $sqlServer.Primary.ResourceName
                DatabaseName                =   $sqlDatabase.ResourceName
                AccessToken                 =   $sqlAccessTokenString
            }
            $dbUsers | Set-AzureSqlAADUser @dbConnectionParams
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
