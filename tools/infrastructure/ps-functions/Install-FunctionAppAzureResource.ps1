function Install-FunctionAppAzureResource {
    <#
      .SYNOPSIS
      Provision the desired state of a function app that uses managed identity for service-to-service authentication
      
      .DESCRIPTION
      Provision the desired state of a function app that uses managed identity for service-to-service authentication.
      This script is written to be idempotent so it is safe to be run multiple times.

      This following Azure resources will be provisioned by this script:

      * Azure Function app
      * User assigned managed identity assigned as the identity for Azure function app
      * Additionally, where `AppRoleDisplayName` has been supplied:
        - Azure AD App registration and associated AD Enterprise app. This App registration is associated with the 
          Azure Function app to authentication requests from other services that also use managed identity
      
      Required permission to run this script:
      * Azure RBAC Role: 'Azure Contributor' and 'User Access Administrator' on
        - resource group for which Azure resource will be created OR
        - subscription IF the resource group does not already exist
      * Additionally, where `AppRoleDisplayName` has been supplied:
        - Azure AD role: 'Application developer'
    
      .PARAMETER ResourceGroup
      The name of the resource group to add the resources to. This group must already exist
          
      .PARAMETER Name
      The name of the function app resource
                
      .PARAMETER ManagedIdentityName
      The name of the user assigned managed identity to use for function app
                      
      .PARAMETER AppRoleDisplayName
      The name display name of an App Role that needs to be granted to consumers (other Azure apps) before they can make
      requests to the function app. If this is supplied then an Azure AD App registration will be provisioned
                      
      .PARAMETER StorageAccountName
      The name of the storage account that the function app will use internally
      
      .PARAMETER TemplateParameterObject
      The parameter values to supplied to the ARM template that deploys the function app
      
      .PARAMETER TemplateDirectory
      The path to the directory containing the ARM templates
      
      .PARAMETER FunctionAppTemplateFile
      The name of the ARM template that will be used to provision the function app.
      (defaults to 'functions-app.json' where a `AppRoleDisplayName` has been supplied otherwise to 'functions-app-no-auth.json')
      
      .PARAMETER ManagedIdentityTemplateFile
      The name of the ARM template that will be used to provision the managed identity used for the function app
      
      .EXAMPLE
      Install-FunctionAppAzureResource -AppRoleDisplayName app_only -ResourceGroup my-app -TemplateDirectory ./tools/infrastructure/arm-templates -InfA Continue
    
      Description
      ----------------
      Creates an Azure function app and associated managed identity along with an AD app registration to authenticate incoming requests to function app
      
      .EXAMPLE
      Install-FunctionAppAzureResource -ResourceGroup my-app -TemplateDirectory ./tools/infrastructure/arm-templates -InfA Continue
    
      Description
      ----------------
      Creates an Azure function app and associated managed identity without an Azure AD app registration

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ResourceGroup,

        [Parameter(Mandatory)]
        [string] $Name,

        [string] $ManagedIdentityName = "$Name-id",
        
        [string] $AppRoleDisplayName,

        [string] $StorageAccountName,

        [Parameter(Mandatory)]
        [string] $TemplateDirectory,
        
        [Hashtable] $TemplateParameterObject = @{},
        
        [string] $FunctionAppTemplateFile,
        
        [Parameter(Mandatory)]
        [string] $ManagedIdentityTemplateFile
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        . "$PSScriptRoot/Invoke-EnsureHttpSuccess.ps1"
        . "$PSScriptRoot/Install-ManagedIdentityAzureResource.ps1"
        . "$PSScriptRoot/Set-ADApplication.ps1"

        $summaryInfo = @{}
        function Add-Summary {
            param([string] $Description, [string] $Value)
            $key = $Description.Replace(' ', '')
            Write-Information "  INFO | $($Description):- $Value"
            $summaryInfo[$key] = $Value
        }
        
        $hasAuth = if ($AppRoleDisplayName) { $true } else { $false }

        if (-not($FunctionAppTemplateFile)) {
            $FunctionAppTemplateFile = if ($hasAuth) { 'functions-app.json' } else { 'functions-app-no-auth.json' }   
        }
        
    }
    process {
        try {
            if (-not(Get-AzContext)) {
                throw 'There is no Azure Account context set. Please make sure to login using Connect-AzAccount'
            }


            #------------- Set user assigned managed identity -------------
            
            $funcManagedIdParams = @{
                ResourceGroup           =   $ResourceGroup
                Name                    =   $ManagedIdentityName
                TemplateFile            =   Join-Path $TemplateDirectory $ManagedIdentityTemplateFile
            }
            $funcManagedId = Install-ManagedIdentityAzureResource @funcManagedIdParams -EA Stop
            Add-Summary 'Function App Managed Identity Client Id' ($funcManagedId.ClientId)
            

            #------------- Set Azure AD app registration -------------
            if ($hasAuth) {
                $funcAdParams = @{
                    IdentifierUri       =   "api://$Name"
                    DisplayName         =   $Name
                    AppRole             =   @{
                        Id                  =   Get-AppRoleId $AppRoleDisplayName $Name
                        AllowedMemberType   =   'Application'
                        DisplayName         =   $AppRoleDisplayName
                        Description         =   'Service-to-Service access'
                        Value               =   'app_only_access'
                        IsEnabled           =   $true
                    }
                }
                $funcAdRegistration = Set-ADApplication -InputObject $funcAdParams
            }


            #------------- Set Function app -------------
            $resourceProviderName = 'Microsoft.Web'
            $unregisteredResoureProvider = Get-AzResourceProvider -ListAvailable -EA Stop |
                    Where-Object { $_.ProviderNamespace -like $resourceProviderName -and $_.RegistrationState -eq 'NotRegistered' }
            if ($unregisteredResoureProvider) {
                Write-Information 'Registering resource providers required to run ARM template...'
                Register-AzResourceProvider -ProviderNamespace $resourceProviderName -EA Stop
            }
            
            $templateParamValues = $TemplateParameterObject + @{
                managedIdentityResourceId   =   $funcManagedId.ResourceId
                functionAppName             =   $Name
            }
            if ($hasAuth) {
                $templateParamValues.appClientId = $funcAdRegistration.AppId
            }
            if ($StorageAccountName) {
                $templateParamValues.storageAccountName = $StorageAccountName
            }
            $funcArmParams = @{
                ResourceGroupName       =   $ResourceGroup
                TemplateParameterObject =   $templateParamValues
                TemplateFile            =   Join-Path $TemplateDirectory $FunctionAppTemplateFile
            }
            Write-Information "Setting Azure Function App '$Name'..."
            New-AzResourceGroupDeployment @funcArmParams -EA Stop | Out-Null
            
            $summaryInfo
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
