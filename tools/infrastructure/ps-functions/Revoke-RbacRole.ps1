function Revoke-RbacRole {
    <#
      .SYNOPSIS
      Revokes Azure RBAC role to a specific scope, skipping where assignment not found
      
      Required permission to run this script: 
      * Azure RBAC Role: 'User Access Administrator'
    
      .PARAMETER Scope
      The Scope of the role assignment. In the format of relative URI. For e.g. "/subscriptions/9004a9fd-d58e-48dc-aeb2-4a4aec58606f/resourceGroups/TestRG". 
      If not specified, will create the role assignment at subscription level. If specified, it should start with "/subscriptions/{id}
          
      .PARAMETER RoleDefinitionName
      Role that is assigned to the principal i.e. Reader, Contributor, Virtual Network Administrator, etc.
      
      .PARAMETER ObjectId
      The Azure AD ObjectId of the User, Group or Service Principal. Filters all assignments that are made to the specified principal.

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Scope,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $RoleDefinitionName,
        
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $ObjectId
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {

            $existing = Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope | Where-Object Scope -eq $Scope
            if (-not($existing)) {
                return
            }

            Write-Information "Removing RBAC role '$RoleDefinitionName' from Identity '$ObjectId'"
            Remove-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -EA Stop | Out-Null
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}