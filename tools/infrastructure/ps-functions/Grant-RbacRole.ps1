function Grant-RbacRole {
    <#
      .SYNOPSIS
      Grants Azure RBAC role to a specific scope, skipping any assignments already made
      
      Required permission to run this script: 
      * Azure RBAC Role: 'User Access Administrator'
    
      .PARAMETER Scope
      The Scope of the role assignment. In the format of relative URI. For e.g. "/subscriptions/9004a9fd-d58e-48dc-aeb2-4a4aec58606f/resourceGroups/TestRG". 
          
      .PARAMETER RoleDefinitionName
      Role that is assigned to the principal i.e. Reader, Contributor, Virtual Network Administrator, etc.
      
      .PARAMETER ObjectId
      The Azure AD ObjectId of the User, Group or Service Principal. Filters all assignments that are made to the specified principal.

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
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

            if (Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope) {
                return
            }

            Write-Information "Assigning RBAC role '$RoleDefinitionName' to Identity '$ObjectId' for scope '$Scope'"
            New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope | Out-Null
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}