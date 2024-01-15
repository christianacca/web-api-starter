function Install-SqlAzureResource {

    <#
      .SYNOPSIS
      Provision the desired state of Azure SQL with Azure Active Directory
      
      .DESCRIPTION
      Provision the desired state of Azure SQL with Azure Active Directory. This script is written to be idempotent so it is safe
      to be run multiple times.

      This following Azure resources will be provisioned by this script:

      * Azure SQL database (logical server and single database) configured with:
        - Azure AD authentication
        - Azure AD Admin mapped to an Azure AD group
      * User assigned managed identity assigned as the identity for Azure SQL Server    

      Required permission to run this script:
      * Azure 'Contributor' on resource group in which Azure resource will be created
      * Azure AD permission: microsoft.directory/groups.security/createAsOwner (or member of 'sg.aad.role.custom.securitygroupcreator' Azure AD group)
      * Owner of Azure AD group 'sg.aad.role.custom.azuresqlauthentication'
        (assumed that 'sg.aad.role.custom.azuresqlauthentication' has been assigned MS Graph directory permissions
        as described here: https://docs.microsoft.com/en-us/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity?view=azuresql#permissions)
    
      .PARAMETER ResourceGroup
      The name of the resource group to add the resources to
      
      .PARAMETER TemplateDirectory
      The path to the directory containing the ARM templates. The following ARM template should exist:
      * azure-sql-server.bicep
      
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
        . "$PSScriptRoot/Set-AADGroup.ps1"

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
            $failoverInfo = if ($SecondarySqlServerName) {
                @{
                    ServerName  =   $SecondarySqlServerName
                    Location    =   $SecondarySqlServerLocation
                }
            } else {
                $null
            }
            $sqlArmParams = @{
                ResourceGroupName       =   $ResourceGroup
                TemplateParameterObject =   @{
                    serverName                      =   $SqlServerName
                    aadAdminName                    =   $AADSqlAdminGroupName
                    aadAdminObjectId                =   $sqlAdAdminGroup.Id
                    aadAdminType                    =   'Group'
                    firewallRules                   =   $FirewallRule
                    location                        =   $ResourceLocation
                    databaseName                    =   $DatabaseName
                    managedIdentityName             =   $ManagedIdentityName
                    failoverInfo                    =   $failoverInfo
                }
                TemplateFile            =   Join-Path $TemplateDirectory azure-sql-server.bicep
            }
            Write-Information "Setting Azure SQL '$SqlServerName'..."
            $deploymentResult = New-AzResourceGroupDeployment @sqlArmParams -EA Stop
            $outputs = [PSCustomObject]$deploymentResult.Outputs
            Add-Summary 'Azure Sql Server Instance Name' "$SqlServerName.database.windows.net"
            Add-Summary 'Azure Sql Database Name' $DatabaseName
            if ($SecondarySqlServerName) {
                Add-Summary 'Azure Sql Server Failover Instance Name' "$SecondarySqlServerName.database.windows.net"
            }
            Add-Summary 'SQL Service Princiapl' $outputs.managedIdentityClientId.Value

            $wait = 15
            Write-Information "Waitinng $wait secconds for new service principal to be propogated before assigning to group"
            Start-Sleep -Seconds $wait
            $groups = [PsCustomObject]@{
                Name                =   'sg.aad.role.custom.azuresqlauthentication'
                Member              = @{
                    ApplicationId       =   $outputs.managedIdentityClientId.Value
                    Type                =   'ServicePrincipal'
                }
            }
            $groups | Set-AADGroup
            
            $summaryInfo

        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
