function Install-SqlAzureResource {

    <#
      .SYNOPSIS
      Provision the desired state of Azure SQL with Azure Active Directory
      
      .DESCRIPTION
      Provision the desired state of Azure SQL with Azure Active Directory. This script is written to be idempotent so it is safe
      to be run multiple times.

      This following Azure resources will be provisioned by this script:

      * User assigned managed identity assigned as the identity for Azure SQL Server
      * Azure SQL database (logical server and single database) configured with:
        - SQL and Azure AD authentication
        - Azure AD Admin mapped to an Azure AD group
        - [Contained] database users mapped to the Azure AD groups above

      Required permission to run this script:
      * Azure 'Contributor' on:
        - resource group for which Azure resource will be created OR
        - subscription IF the resource group does not already exist
      * Azure AD 'Privileged role administrator' (required for assigning MS Graph directory permissions to Azure SQL service)
    
      .PARAMETER ResourceGroup
      The name of the resource group to add the resources to. If the resource group is not found a new one will be
      created with this name
      
      .PARAMETER TemplateDirectory
      The path to the directory containing the ARM templates. The following ARM templates should exist:
      * sql-managed-identity.json
      * azure-sql-server.json
      * azure-sql-failover.json
      * azure-sql-db.json       
      
      .PARAMETER ResourceLocation
      The region to create the Azure resources within
    
      .PARAMETER SqlServerName
      The name of the Azure SQL Server. This will become the instance name <SqlServerName>.database.windows.net

      .PARAMETER DatabaseName
      The name of the Azure SQL database
        
      .PARAMETER SecondarySqlServerName
      The name of a secondary Azure SQL Server that will be paired as a failover
    
      .PARAMETER SecondarySqlServerLocation
      The Azure region for the secondary Azure SQL Server
            
      .PARAMETER ManagedIdentityName
      The name of the user assigned managed identity that will be used as the identity for the Azure SQL server
    
      .PARAMETER AADSqlAdminGroupName
      The name of Azure Active Directory Group that will be used as the AAD SQL Admin for the SQL database. By default the
      current user signed in via Connect-AzAccount will be added as a member of this group. To stop this default behaviour
      supply SkipIncludeCurrentUserInAADSqlAdminGroup switch
     
      .PARAMETER FirewallRule
      The firewall rules that control which IP can access the Azure SQL server
      
      .PARAMETER AllowAllAzureServices
      Add the 'Allow all Azure services to access this server' firewall rule
       
      .PARAMETER SkipIncludeCurrentIPAddressInSQLFirewall
      Skip adding the allow current IP address as a firewall rule
 
      .EXAMPLE
      Install-SqlAzureResource -ResourceGroup my-resource-group -InformationAction Continue
    
      Description
      ----------------
      Creates all the Azure resources in the resource group supplied, displaying to the console details of the task execution.

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ResourceGroup,

        [Parameter(Mandatory)]
        [string] $TemplateDirectory,

        [string] $ResourceLocation = 'eastus',

        [string] $SqlServerName = "$ResourceGroup-sql",
        
        [string] $DatabaseName = "$SqlServerName-db",
        
        [string] $SecondarySqlServerName,
        
        [string] $SecondarySqlServerLocation,
        
        [string] $ManagedIdentityName = "$SqlServerName-id",

        [string] $AADSqlAdminGroupName = "grp-$SqlServerName-admin",
        
        [Hashtable[]] $FirewallRule = @(),

        [switch] $AllowAllAzureServices,
        
        [switch] $SkipIncludeCurrentIPAddressInSQLFirewall
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/Invoke-Exe.ps1"
        . "$PSScriptRoot/Invoke-EnsureHttpSuccess.ps1"

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

            $currentAzContext = Get-AzContext -EA Stop
            if (-not($currentAzContext)) {
                throw 'There is no Azure Account context set. Please make sure to login using Connect-AzAccount'
            }
            
            if (-not(Get-AzResourceGroup $ResourceGroup)) {
                Write-Information "Creating Azure Resource Group '$ResourceGroup'..."
                New-AzResourceGroup $ResourceGroup $ResourceLocation -EA Stop | Out-Null
            }


            #------------- Set user assigned managed identities -------------
            $managedIdArmParams = @{
                ResourceGroup           =   $ResourceGroup
                Name                    =   $ManagedIdentityName
                TemplateFile            =   Join-Path $TemplateDirectory sql-managed-identity.json
            }
            $sqlManagedId = Install-ManagedIdentityAzureResource @managedIdArmParams -EA Stop


            #-------------  Assign MS Graph permissions to sql managed identity -------------
            # For more information why see: https://docs.microsoft.com/en-us/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity

            $msGraphServicePrinciapl = Get-AzADServicePrincipal -DisplayName 'Microsoft Graph' -EA Stop
            $msGraphAppRoles = $msGraphServicePrinciapl.AppRole |
                Where-Object Value -in 'User.Read.All', 'GroupMember.Read.All', 'Application.Read.All'

            # Replace '***** Update-AzADServicePrincipal WORKAROUND' with this commented out code once 
            # `Update-AzADServicePrincipal` has implemented `AppRoleAssignment` parameter
#            $sqlMsGraphAppRoleAssignmentParams = @{
#                ObjectId                =   $msGraphServicePrinciapl.Id
#                AppRoleAssignment       =   $msGraphAppRoles | ForEach-Object {
#                    @{
#                        ResourceId  =   $msGraphServicePrinciapl.Id
#                        AppRoleId   =   $_.Id
#                        PrincipalId =   $sqlManagedId.PrincipalId
#                    }
#                }
#            }
#            Write-Information "Assigning AD App role to SQL managed identity..."
#            Update-AzADServicePrincipal @$sqlMsGraphAppRoleAssignmentParams -EA Stop

            # ***** BEGIN Update-AzADServicePrincipal WORKAROUND
            $appRoleAssignmentUrl = "https://graph.microsoft.com/v1.0/servicePrincipals/$($sqlManagedId.PrincipalId)/appRoleAssignments"

            Start-Sleep -Seconds 15 # allow for managed identity created above to be replicated
            Write-Information "Searching for MS Graph app role assignment for sql..."
            $existingAppRoleAssignments = { Invoke-AzRestMethod -Uri $appRoleAssignmentUrl -EA Stop } |
                Invoke-EnsureHttpSuccess |
                ConvertFrom-Json |
                Select-Object -ExpandProperty value

            $unassignedAppRoles = $msGraphAppRoles |
                Where-Object Id -NotIn ($existingAppRoleAssignments | Select-Object -ExpandProperty appRoleId)
            if ($unassignedAppRoles) {
                $unassignedAppRoles | ForEach-Object {
                    
                    $appRoleAssignmentJson = @{
                        principalId =   $sqlManagedId.PrincipalId
                        resourceId  =   $msGraphServicePrinciapl.Id
                        appRoleId   =   $_.Id
                    } | ConvertTo-Json -Compress
                    
                    Write-Information "Assigning MS Graph app roles to sql managed identity..."
                    { Invoke-AzRestMethod -Method POST -Uri $appRoleAssignmentUrl -Payload $appRoleAssignmentJson -EA Stop } |
                        Invoke-EnsureHttpSuccess | Out-Null
                }
            }
            # ***** END Update-AzADServicePrincipal WORKAROUND
            

            #------------- Set Azure SQL Server -------------
            $sqlAdAdminGroup = Get-AzADGroup -DisplayName $AADSqlAdminGroupName
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
            $allAzureServicesRule = if ($AllowAllAzureServices) {
                @{
                    StartIpAddress  =   '0.0.0.0'
                    EndIpAddress    =   '0.0.0.0'
                    Name            =   'AllowAllWindowsAzureIps'
                }
            } else {
                @()
            }
            $FirewallRule = @($FirewallRule; $allAzureServicesRule; $currentIpRule)
            $sqlArmParams = @{
                ResourceGroupName       =   $ResourceGroup
                TemplateParameterObject =   @{
                    serverName                      =   $SqlServerName
                    aadAdminName                    =   $AADSqlAdminGroupName
                    aadAdminObjectId                =   $sqlAdAdminGroup.Id
                    aadAdminType                    =   'Group'
                    managedIdentityResourceId       =   $sqlManagedId.ResourceId
                    firewallRules                   =   $FirewallRule
                    location                        =   $ResourceLocation
                }
                TemplateFile            =   Join-Path $TemplateDirectory azure-sql-server.json
            }
            Write-Information "Setting Azure SQL '$SqlServerName'..."
            # Retry logic added because it's not uncommon to receive the following failure when creating:
            # "... The operation on the resource could not be completed because it was interrupted by another operation on the same resource"
            try {
                New-AzResourceGroupDeployment @sqlArmParams -EA Continue | Out-Null
            }
            catch {
                Write-Warning "  Azure SQL server provisioning failed... retrying"
                New-AzResourceGroupDeployment @sqlArmParams -EA Stop | Out-Null
            }
            New-AzResourceGroupDeployment @sqlArmParams -EA Stop | Out-Null
            Add-Summary 'Azure Sql Server Instance Name' "$SqlServerName.database.windows.net"


            #------------- Set Azure SQL Server Database -------------
            # Note: we're splitting the provisioning of the Azure SQL Server and it's db into seperate ARM templates
            # to reduce the chance of receiving the failure noted above
            $sqlDbArmParams = @{
                ResourceGroupName       =   $ResourceGroup
                TemplateParameterObject =   @{
                    serverName      =   $SqlServerName
                    databaseName    =   $DatabaseName
                    location        =   $ResourceLocation
                }
                TemplateFile            =   Join-Path $TemplateDirectory azure-sql-db.json
            }
            Write-Information "Setting Azure SQL DB '$DatabaseName'..."
            New-AzResourceGroupDeployment @sqlDbArmParams -EA Continue | Out-Null
            Add-Summary 'Azure Sql Database Name' $DatabaseName
            
            
            if ($SecondarySqlServerName) {
                $sql2ArmParams = @{
                    ResourceGroupName       =   $ResourceGroup
                    TemplateParameterObject =   @{
                        sqlServerPrimaryName            =   $SqlServerName
                        sqlServerSecondaryName          =   $SecondarySqlServerName
                        sqlServerSecondaryRegion        =   $SecondarySqlServerLocation
                        sqlFailoverGroupName            =   "$DatabaseName-fg"
                        databaseName                    =   $DatabaseName
                        aadAdminName                    =   $AADSqlAdminGroupName
                        aadAdminObjectId                =   $sqlAdAdminGroup.Id
                        aadAdminType                    =   'Group'
                        managedIdentityResourceId       =   $sqlManagedId.ResourceId
                        firewallRules                   =   $FirewallRule
                    }
                    TemplateFile            =   Join-Path $TemplateDirectory azure-sql-failover.json
                }
                Write-Information "Setting Azure SQL '$SecondarySqlServerName'..."
                New-AzResourceGroupDeployment @sql2ArmParams -EA Stop | Out-Null
                Add-Summary 'Azure Sql Server Failover Instance Name' "$SecondarySqlServerName.database.windows.net"
            }
            
            
            $summaryInfo

        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
