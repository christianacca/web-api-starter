function Install-FunctionAppAzureResource {
    <#
      .SYNOPSIS
      Provision the desired state of a function app that uses managed identity for service-to-service authentication
      
      .DESCRIPTION
      Provision the desired state of a function app that uses managed identity for service-to-service authentication.
      This script is written to be idempotent so it is safe to be run multiple times.

      This following Azure resources will be provisioned by this script:

      * Azure Function app
      * Azure AD App registration and associated AD Enterprise app. This App registration is associated with the Azure Function
        app to authentication requests from other services that also use managed identity
      * User assigned managed identity assigned as the identity for Azure function app
      
      Required permission to run this script:
      * Azure Contributor and User Access Administrator on:
        - resource group for which Azure resource will be created OR
        - subscription IF the resource group does not already exist
      * Azure AD Application administrator
    
      .PARAMETER ResourceGroup
      The name of the resource group to add the resources to. This group must already exist
          
      .PARAMETER Name
      The name of the function app resource
                
      .PARAMETER ManagedIdentityName
      The name of the user assigned managed identity to use for function app
                      
      .PARAMETER AppRoleDisplayName
      The name display name of an App Role that needs to be granted to consumers (other Azure apps) before they can make
      requests to the function app
      
      .PARAMETER TemplateDirectory
      The path to the directory containing the ARM templates. The following ARM templates should exist:
      * functions-app.json
      * functions-managed-identity.json
      
      .EXAMPLE
      Install-FunctionAppAzureResource -ResourceGroup my-app -TemplateDirectory ./tools/infrastructure/arm-templates -InfA Continue
    
      Description
      ----------------
      Creates all the Azure resources in the resource group supplied, displaying to the console details of the task execution

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ResourceGroup,

        [Parameter(Mandatory)]
        [string] $Name,

        [string] $ManagedIdentityName = "$Name-id",
        
        [Parameter(Mandatory)]
        [string] $AppRoleDisplayName,

        [Parameter(Mandatory)]
        [string] $TemplateDirectory
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        . "$PSScriptRoot/Invoke-EnsureHttpSuccess.ps1"
        . "$PSScriptRoot/Install-ManagedIdentityAzureResource.ps1"

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
            if (-not(Get-AzContext)) {
                throw 'There is no Azure Account context set. Please make sure to login using Connect-AzAccount'
            }


            #------------- Set user assigned managed identity -------------
            
            $funcManagedIdParams = @{
                ResourceGroup           =   $ResourceGroup
                Name                    =   $ManagedIdentityName
                TemplateFile            =   Join-Path $TemplateDirectory functions-managed-identity.json
            }
            $funcManagedId = Install-ManagedIdentityAzureResource @funcManagedIdParams -EA Stop
            Add-Summary 'Function App Managed Identity Client Id' ($funcManagedId.ClientId)
            

            #------------- Set Azure AD app registration -------------
            Write-Information "Searching for existing Azure AD App registration for function app..."
            $funcAdRegistration = Get-AzADApplication -DisplayName $Name -EA Stop
            $funcAdParams = @{
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
            if (-not($funcAdRegistration)) {
                Write-Information "  Existing AD App registration not found. Creating..."
                $funcAdRegistration = New-AzADApplication @funcAdParams -EA Stop
            } else {
                Write-Information "  Existing AD App registration found '$($funcAdRegistration.Id)'. Skipping create"
            }

            Write-Information "Updating Azure Function App AD Registration '$Name' with additional configuration..."
            $appUri = "api://$($funcAdRegistration.AppId)"
            Update-AzADApplication -ApplicationId ($funcAdRegistration.AppId) -IdentifierUri $appUri -EA Stop | Out-Null
            Add-Summary 'Function App Application Id' ($funcAdRegistration.AppId)

            Write-Information "Searching for existing Azure AD App service principal for function app..."
            $funcAdAppServicePrincipal = Get-AzADServicePrincipal -ApplicationId ($funcAdRegistration.AppId) -EA Stop
            if (-not($funcAdAppServicePrincipal)) {
                Write-Information "  Existing service principal not found. Creating service principal for AD App rgistration ($($funcAdRegistration.AppId))..."
                $funcAdAppServicePrincipal = New-AzADServicePrincipal -ApplicationId ($funcAdRegistration.AppId) -AppRoleAssignmentRequired -EA Stop

                # Delete '***** New-AzADServicePrincipal WORKAROUND' once `New-AzADServicePrincipal`
                # has implemented `AppRoleAssignmentRequired` parameter

                # ***** BEGIN New-AzADServicePrincipal WORKAROUND
                $serivePrincipalUpdateJson = @{
                    appRoleAssignmentRequired   =   $true
                } | ConvertTo-Json

                $serivePrincipalUpdateUrl = "https://graph.microsoft.com/v1.0/servicePrincipals/$($funcAdAppServicePrincipal.Id)"
                { Invoke-AzRestMethod -Method PATCH -Uri $serivePrincipalUpdateUrl -Payload $serivePrincipalUpdateJson -EA Stop } |
                    Invoke-EnsureHttpSuccess | Out-Null
                # ***** END New-AzADServicePrincipal WORKAROUND
            } else {
                Write-Information "  Existing AD App service principal found '$($funcAdAppServicePrincipal.Id)'. Skipping create"
            }


            #------------- Set Function app -------------
            $resourceProviderName = 'Microsoft.Web'
            $unregisteredResoureProvider = Get-AzResourceProvider -ListAvailable -EA Stop |
                    Where-Object { $_.ProviderNamespace -like $resourceProviderName -and $_.RegistrationState -eq 'NotRegistered' }
            if ($unregisteredResoureProvider) {
                Write-Information 'Registering resource providers required to run ARM template...'
                Register-AzResourceProvider -ProviderNamespace $resourceProviderName -EA Stop
            }
            
            $funcArmParams = @{
                ResourceGroupName       =   $ResourceGroup
                TemplateParameterObject =   @{
                    managedIdentityResourceId   =   $funcManagedId.ResourceId
                    functionAppName             =   $Name
                    appClientId                 =   $funcAdRegistration.AppId
                }
                TemplateFile            =   Join-Path $TemplateDirectory functions-app.json
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
