function Revoke-ADAppRolePermission {
    <#
      .SYNOPSIS
      Revokes the AD App role declared by an AD App registration from a manged identity 
      
      .DESCRIPTION
      Revokes the AD App role beloging to a AD App registration from a manged identity . This script is written 
      to be idempotent so it is safe to be run multiple times.
      
      Required permission to run this script:
      * Azure AD Application administrator
    
      .PARAMETER TargetAppDisplayName
      The name of the AD App registration that declares the app role that is to be revoked
      
      .PARAMETER AppRoleId
      The id of the app role to be revoked
      
      .PARAMETER ManagedIdentityDisplayName
      The display name of the managed identity to revoke the app role from. Required when ManagedIdentityObjectId is not specified
            
      .PARAMETER ManagedIdentityResourceGroupName
      The resource group containing the managed identity. Required when ManagedIdentityObjectId is not specified
                  
      .PARAMETER ManagedIdentityObjectId
      The object id of the managed managed identity to revoke the app role from.
      Required when ManagedIdentityDisplayName and ManagedIdentityResourceGroupName is not specified
      
      .EXAMPLE
      Revoke-ADAppRolePermission -TargetAppDisplayName web-api-starter-func -AppRoleId xxx-xxx-xxx -ManagedIdentityDisplayName web-api-starter-api -ManagedIdentityResourceGroupName web-api-starter
   
      Description
      -----------
      Revokes app role ($AppRoleId) exposed by the AD app registration 'web-api-starter-func' from the managed identity
      that is identified by the display name of 'web-api-starter-api' in the resource group 'web-api-starter'
      
      .EXAMPLE
      Revoke-ADAppRolePermission -TargetAppDisplayName web-api-starter-func -AppRoleId xxx-xxx-xxx -ManagedIdentityObjectId xxx-xxx-yyy
   
      Description
      -----------
      Revokes app role ($AppRoleId) exposed by the AD app registration 'web-api-starter-func' from the managed identity
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
      $appRoleGrants | Revoke-ADAppRolePermission -TargetAppDisplayName web-api-starter-func -AppRoleId xxx-xxx-xxx
   
      Description
      -----------
      Revokes multiple managed identities from the app role ($AppRoleId) exposed by the AD app registration 'web-api-starter-func'
      
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
            $appRoleAssignmentUrl = "https://graph.microsoft.com/v1.0/servicePrincipals/$($targetAppServicePrincipal.Id)/appRoleAssignedTo"

            Write-Information "Searching for AD app role assignment for AD App registration '$TargetAppDisplayName'..."
            $existingAppRoleAssignments = { Invoke-AzRestMethod -Uri $appRoleAssignmentUrl -EA Stop } |
                Invoke-EnsureHttpSuccess |
                ConvertFrom-Json |
                Select-Object -ExpandProperty value

            $funcAppAdRole = $existingAppRoleAssignments |
                Where-Object { $_.appRoleId -eq $AppRoleId -and $_.principalId -eq $ManagedIdentityObjectId }
            if (-not($funcAppAdRole)) {
                Write-Information "Removing AD app role '$AppRoleId' exposed by '$TargetAppDisplayName' app from managed identity '$ManagedIdentityObjectId'..."
                { Invoke-AzRestMethod -Method DELETE -Uri "$appRoleAssignmentUrl/$($funcAppAdRole.id)" -EA Stop } |
                    Invoke-EnsureHttpSuccess | Out-Null
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}