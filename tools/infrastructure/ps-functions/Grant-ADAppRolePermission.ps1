function Grant-ADAppRolePermission {
    <#
      .SYNOPSIS
      Grants the AD App role declared by an AD App registration to a manged identity 
      
      .DESCRIPTION
      Grants the AD App role beloging to a AD App registration to a manged identity . This script is written 
      to be idempotent so it is safe to be run multiple times.
      
      Required permission to run this script:
      * Azure AD Application administrator
    
      .PARAMETER TargetAppDisplayName
      The name of the AD App registration that declares the app role that is to be granted
      
      .PARAMETER AppRoleId
      The id of the app role to be granted
      
      .PARAMETER ManagedIdentityDisplayName
      The display name of the managed identity to grant the app role to. Required when ManagedIdentityObjectId is not specified
            
      .PARAMETER ManagedIdentityResourceGroupName
      The resource group containing the managed identity. Required when ManagedIdentityObjectId is not specified
                  
      .PARAMETER ManagedIdentityObjectId
      The object id of the managed managed identity to grant the app role to.
      Required when ManagedIdentityDisplayName and ManagedIdentityResourceGroupName is not specified
      
      .EXAMPLE
      Grant-ADAppRolePermission -TargetAppDisplayName web-api-starter-func -AppRoleId xxx-xxx-xxx -ManagedIdentityDisplayName web-api-starter-api -ManagedIdentityResourceGroupName web-api-starter
   
      Description
      -----------
      Assign app role ($AppRoleId) exposed by the AD app registration 'web-api-starter-func' to the managed identity
      that is identified by the display name of 'web-api-starter-api' in the resource group 'web-api-starter'
      
      .EXAMPLE
      Grant-ADAppRolePermission -TargetAppDisplayName web-api-starter-func -AppRoleId xxx-xxx-xxx -ManagedIdentityObjectId xxx-xxx-yyy
   
      Description
      -----------
      Assign app role ($AppRoleId) exposed by the AD app registration 'web-api-starter-func' to the managed identity
      with object id 'xxx-xxx-yyy'
            
      .EXAMPLE
      $appRoleGrants = @(
        [PSCustomObject]@{
          ManagedIdentityDisplayName          =   'id-aig-dev-api'
          ManagedIdentityResourceGroupName    =   'rg-dev-aig-eastus'
        }
        [PSCustomObject]@{
          ManagedIdentityObjectId =   'bab5e655-a79d-4e3a-a1a0-7ba68e5cf698'
        }
      )
      $appRoleGrants | Grant-ADAppRolePermission -TargetAppDisplayName web-api-starter-func -AppRoleId xxx-xxx-xxx
   
      Description
      -----------
      Assign multiple managed identities to the app role ($AppRoleId) exposed by the AD app registration 'web-api-starter-func'
      
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $TargetAppDisplayName,
        
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $AppRoleId,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $ManagedIdentityDisplayName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $ManagedIdentityResourceGroupName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $ManagedIdentityObjectId
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        . "$PSScriptRoot/Invoke-EnsureHttpSuccess.ps1"
    }
    process {
        try {
            if (-not(Get-AzContext)) {
                throw 'There is no Azure Account context set. Please make sure to login using Connect-AzAccount'
            }

            $ManagedIdentityObjectId = if (-not($ManagedIdentityObjectId)) {
                Get-AzUserAssignedIdentity -Name $ManagedIdentityDisplayName -ResourceGroupName $ManagedIdentityResourceGroupName -EA Stop |
                    Select-Object -ExpandProperty PrincipalId
            } else {
                $ManagedIdentityObjectId
            }
            if (-not($ManagedIdentityObjectId)) {
                throw "Managed identity to assign app role to not found by the name of '$ManagedIdentityDisplayName' in resource group '$ManagedIdentityResourceGroupName'"
            }

            $targetAppAdRegistration = Get-AzADApplication -DisplayName $TargetAppDisplayName -EA Stop
            if (-not($targetAppAdRegistration)) {
                throw "Target AD App registrationnot found by the name of '$TargetAppDisplayName'"
            }

            $targetAppServicePrincipal = Get-AzADServicePrincipal -ApplicationId ($targetAppAdRegistration.AppId) -EA Stop
            if (-not($targetAppAdRegistration)) {
                throw "No Service Prinicipal associated with AD App registration '$TargetAppDisplayName'"
            }

            #------------- Assign AD app role for target app to managed identity -------------
            # Replace '***** Update-AzADServicePrincipal WORKAROUND' below with this commented out code once 
            # `Update-AzADServicePrincipal` has implemented `AppRoleAssignment` parameter
#            $targetAppRoleAssignmentParams = @{
#                ObjectId                    =   $targetAppServicePrincipal.Id
#                AppRoleAssignment         =   @{
#                    ResourceId  =   $targetAppServicePrincipal.Id
#                    AppRoleId   =   $AppRoleId
#                    PrincipalId =   $ManagedIdentityObjectId
#                }
#            }
#            Write-Information "Assigning function app AD App role to API managed identity..."
#            Update-AzADServicePrincipal @$targetAppRoleAssignmentParams -EA Stop

            # ***** BEGIN Update-AzADServicePrincipal WORKAROUND
            $appRoleAssignmentUrl = "https://graph.microsoft.com/v1.0/servicePrincipals/$($targetAppServicePrincipal.Id)/appRoleAssignedTo"

            Write-Information "Searching for AD app role assignment for AD App registration '$TargetAppDisplayName'..."
            $existingAppRoleAssignments = { Invoke-AzRestMethod -Uri $appRoleAssignmentUrl -EA Stop } |
                Invoke-EnsureHttpSuccess |
                ConvertFrom-Json |
                Select-Object -ExpandProperty value

            $funcAppAdRole = $existingAppRoleAssignments |
                Where-Object { $_.appRoleId -eq $AppRoleId -and $_.principalId -eq $ManagedIdentityObjectId }
            if (-not($funcAppAdRole)) {
                $appRoleAssignmentJson = @{
                    principalId =   $ManagedIdentityObjectId
                    resourceId  =   $targetAppServicePrincipal.Id
                    appRoleId   =   $AppRoleId
                } | ConvertTo-Json -Compress

                Write-Information "Assigning AD app role '$AppRoleId' exposed by '$TargetAppDisplayName' app to managed identity '$ManagedIdentityObjectId'..."
                { Invoke-AzRestMethod -Method POST -Uri $appRoleAssignmentUrl -Payload $appRoleAssignmentJson -EA Stop } |
                    Invoke-EnsureHttpSuccess | Out-Null
            }
            # ***** END Update-AzADServicePrincipal WORKAROUND
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
