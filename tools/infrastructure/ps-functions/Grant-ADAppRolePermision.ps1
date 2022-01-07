function Grant-ADAppRolePermision {
    <#
      .SYNOPSIS
      Grants the AD App role declared by an AD App registration to a manged identity 
      
      .DESCRIPTION
      Grants the AD App role beloging to a AD App registration to a manged identity . This script is written 
      to be idempotent so it is safe to be run multiple times.
      
      Required permission to run this script:
      * Azure AD Application administrator
    
      .PARAMETER TargetAppDisplayName
      The name of the AD App registration that declares the app role is to be granted
      
      .PARAMETER AppRoleId
      The id of the app role to be granted
      
      .PARAMETER ManagedIdentityDisplayName
      The display name of the managed identity to grant the app role to
            
      .PARAMETER ManagedIdentityResourceGroupName
      The resource group containing the managed identity
      
      .EXAMPLE
      Grant-ADAppRolePermision -TargetAppDisplayName web-api-starter-func -AppRoleId xxx-xxx-xxx ManagedIdentityDisplayName web-api-starter-api -ManagedIdentityResourceGroupName web-api-starter

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $TargetAppDisplayName,
        
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $AppRoleId,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $ManagedIdentityDisplayName,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $ManagedIdentityResourceGroupName
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
            
            $managedId = Get-AzUserAssignedIdentity -Name $ManagedIdentityDisplayName -ResourceGroupName $ManagedIdentityResourceGroupName -EA Stop
            if (-not($managedId)) {
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
#                    PrincipalId =   $managedId.PrincipalId
#                }
#            }
#            Write-Information "Assigning function app AD App role to API managed identity..."
#            Update-AzADServicePrincipal @$targetAppRoleAssignmentParams -EA Stop

            # ***** BEGIN Update-AzADServicePrincipal WORKAROUND
            $appRoleAssignmentUrl = "https://graph.microsoft.com/v1.0/servicePrincipals/$($managedId.PrincipalId)/appRoleAssignments"

            Write-Information "Searching for AD app role assignment for function app..."
            $existingAppRoleAssignments = { Invoke-AzRestMethod -Uri $appRoleAssignmentUrl -EA Stop } |
                Invoke-EnsureHttpSuccess |
                ConvertFrom-Json |
                Select-Object -ExpandProperty value

            $funcAppAdRole = $existingAppRoleAssignments | Where-Object appRoleId -eq $AppRoleId
            if (-not($funcAppAdRole)) {
                $appRoleAssignmentJson = @{
                    principalId =   $managedId.PrincipalId
                    resourceId  =   $targetAppServicePrincipal.Id
                    appRoleId   =   $AppRoleId
                } | ConvertTo-Json -Compress

                Write-Information "Assigning AD app role for target '$TargetAppDisplayName' app to managed identity..."
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
