    <#
      .SYNOPSIS
      Provision the desired state of the application stack in Azure
      
      .DESCRIPTION
      Provision the desired state of the application stack in Azure. This script is written to be idempotent so it is safe
      to be run multiple times.
      
      This following Azure resources will be provisioned by this script:
      
      * User assgined managed identity that are bound to Azure container apps
      * Azure Function app x2 ('internalapi', 'testpbi')
      * User assigned managed identity assigned as the identity for Azure function apps
      * Azure AD App registration and associated AD Enterprise app (aka service principal). This App registration is associated with the 
        Azure Function app 'internalapi' to authentication requests from the Azure container apps
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
    
      .PARAMETER BuildVersion
      The version number to assign to the resource group.

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

        [string] $BuildVersion = '0.0.0',

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

        . "$PSScriptRoot/ps-functions/Get-AcaAppInfoVars.ps1"
        . "$PSScriptRoot/ps-functions/Get-AzModuleInfo.ps1"
        . "$PSScriptRoot/ps-functions/Get-CurrentUserAsMember.ps1"
        . "$PSScriptRoot/ps-functions/Get-RbacRoleAssignment.ps1"
        . "$PSScriptRoot/ps-functions/Get-ScriptDependencyList.ps1"
        . "$PSScriptRoot/ps-functions/Get-ServicePrincipalAccessToken.ps1"
        . "$PSScriptRoot/ps-functions/Grant-RbacRole.ps1"
        . "$PSScriptRoot/ps-functions/hashtable-functions.ps1"
        . "$PSScriptRoot/ps-functions/Invoke-Exe.ps1"
        . "$PSScriptRoot/ps-functions/Install-ScriptDependency.ps1"
        . "$PSScriptRoot/ps-functions/Resolve-RbacRoleAssignment.ps1"
        . "$PSScriptRoot/ps-functions/Set-AADGroup.ps1"
        . "$PSScriptRoot/ps-functions/Set-AzureAccountContext.ps1"
        . "$PSScriptRoot/ps-functions/Set-AzureResourceGroup.ps1"
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

            Set-AzureAccountContext -Login:$Login -SubscriptionId $SubscriptionId

            # Tip: you can also print out listing for the conventions. See the examples in ./tools/infrastructure/print-product-convention-table.ps1
            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable

            #-----------------------------------------------------------------------------------------------
            Write-Information '0. Print environment information...'
            $standaloneBicepVs = Invoke-Exe { bicep --version } -EA Continue
            Write-Information "  INFO | Standalone Bicep version: $($standaloneBicepVs)"
            $azBicepVs = Invoke-Exe { az bicep version } -EA Continue
            Write-Information "  INFO | Azure CLI Bicep version: $($azBicepVs)"
            
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
                Get-AzAccessToken -ResourceUrl $sqlTokenResourceUrl -AsSecureString -EA Stop
            }
            Write-Information "  INFO | Token ExpiresOn: $($sqlAccessToken.ExpiresOn)"
            Write-Information "  INFO | Token TenantId: $($sqlAccessToken.TenantId)"
            Write-Information "  INFO | Token UserId: $($sqlAccessToken.UserId)"
            $sqlAccessTokenCreds = [PSCredential]::new("token", $sqlAccessToken.Token)


            #-----------------------------------------------------------------------------------------------
            Write-Information '3. Set resource group...'
            $appResourceGroup = $convention.AppResourceGroup
            $resourceGroupParams = @{
                Name        =   $appResourceGroup.ResourceName
                Location    =   $appResourceGroup.ResourceLocation
                Tag         =   @{
                    Version     =   $BuildVersion
                }
                MergeTag    =   $true # other departments have added tags to the resource group that we probably don't want to remove
            }
            $rg = Set-AzureResourceGroup @resourceGroupParams -EA Stop


            #-----------------------------------------------------------------------------------------------
            Write-Information '4. Set AAD groups - for Teams...'
            $teamGroups = @(
                $convention.TeamGroups.Values
                $convention.SubProducts.Values | ForEach-Object { $_['TeamGroups'] } | Select-Object -ExpandProperty Values
            )
            $teamGroups | Set-AADGroup | Out-Null


            #-----------------------------------------------------------------------------------------------
            Write-Information "5. Set Azure RBAC - for teams to scope '$($rg.ResourceId)'..."
            $wait = 15
            Write-Information "Waitinng $wait secconds for new identities and/or groups to be propogated before assigning RBAC"
            Start-Sleep -Seconds $wait
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
            Write-Information '7. Set Azure resources...'
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
            
            Write-Information "  Gathering existing resource information..."
            $mainArmTemplateParams = @(
                @{
                    settings                    =   $convention
                    sqlAdAdminGroupObjectId     =   $sqlAdAdminGroup.Id
                }
                Get-AcaAppInfoVars $convention -SubProductName Api
                Get-AcaAppInfoVars $convention -SubProductName App
            )
            
            $mainArmParams = @{
                ResourceGroupName       =   $appResourceGroup.ResourceName
                TemplateParameterObject =   $mainArmTemplateParams | Join-Hashtable
                TemplateFile            =   Join-Path $templatePath main.bicep
            }
            if ($WhatIfAzureResourceDeployment) {
                Write-Information '  Print Azure resource desired state changes only...'
                New-AzResourceGroupDeployment @mainArmParams -WhatIf -WhatIfExcludeChangeType Ignore, NoChange, Unsupported -EA Stop
                return
            }
            Write-Information '  Creating desired resource state'
            $armResources = New-AzResourceGroupDeployment @mainArmParams -EA Stop | ForEach-Object { $_.Outputs }
            Write-Information "  INFO | App Managed Identity Client Id:- $($armResources.appManagedIdentityClientId.Value)"
            Write-Information "  INFO | Api Managed Identity Client Id:- $($armResources.apiManagedIdentityClientId.Value)"
            Write-Information "  INFO | Internal Api Managed Identity Client Id:- $($armResources.internalApiManagedIdentityClientId.Value)"
            Write-Information "  INFO | 'Azure SQL Managed Identity Client Id':- $($armResources.sqlManagedIdentityClientId.Value)"


            #-----------------------------------------------------------------------------------------------
            Write-Information '8. Set AAD groups - for resources (post-resource creation)...'

            $wait = 15
            Write-Information "Waitinng $wait secconds for new identities and/or groups to be propogated before assigning group membership"
            Start-Sleep -Seconds $wait

#            $pbiGroups = $convention.SubProducts.Pbi.AadSecurityGroup | ForEach-Object { [PsCustomObject]$_ }
#            $pbiAppGroup = $pbiGroups | Where-Object Name -like "*.app"
#            $pbiAppGroup.Member = @(
#                @{
#                    ApplicationId       =   $armResources.apiManagedIdentityClientId.Value
#                    Type                =   'ServicePrincipal'
#                }
#            ) + $pbiAppGroup.Member

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
                    ApplicationId       =   $armResources.appManagedIdentityClientId.Value
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

#            @($pbiGroups; $sqlGroups; $sqlAadAuthGroup) | Set-AADGroup | Out-Null
            @($sqlGroups; $sqlAadAuthGroup) | Set-AADGroup | Out-Null


            #-----------------------------------------------------------------------------------------------
            Write-Information '9. Set Data plane operations...'

            # Azure SQL users
            Write-Information 'Setting Azure SQL users logins...'
            $dbUsers = $sqlDatabase.AadSecurityGroup | ForEach-Object { [PsCustomObject]$_ }
            $dbConnectionParams = @{
                SqlServerName               =   $sqlServer.Primary.ResourceName
                DatabaseName                =   $sqlDatabase.ResourceName
                AccessTokenCredential       =   $sqlAccessTokenCreds
            }
            $dbUsers | Set-AzureSqlAADUser @dbConnectionParams
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
