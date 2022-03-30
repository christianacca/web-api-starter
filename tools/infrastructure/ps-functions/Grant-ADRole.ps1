function Grant-ADRole {
    <#
      .SYNOPSIS
      Assign Azure AD role to a principal

      .DESCRIPTION
      Assign Azure AD role to a principal.
      This function is idempotent - any roles already assigned to the prinicpal will be skipped.
    
      .PARAMETER PrincipalId
      The ID of the prinicpal that is to be assigned the role(s)
      
      .PARAMETER PrincipalType
      The type of the principal
      
      .PARAMETER RoleDefinitionId
      The ID of the Azure AD role to assign 
      For list of available ID's see: https://docs.microsoft.com/en-us/azure/active-directory/roles/permissions-reference
      
      .PARAMETER RoleDefinitionDisplayName
      The friendly name of the Azure AD role to assign 

      .EXAMPLE
      $roles = @(
        [PsCustomObject]@{
            RoleDefinitionId            = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3'
            RoleDefinitionDisplayName   = 'Application administrator'
        }
        [PsCustomObject]@{
            RoleDefinitionId            = 'fdd7a751-b60b-444a-984c-02652fe8fa1c'
            RoleDefinitionDisplayName   = 'Groups administrator'
        }
      )
      $roles | Grant-ADRole -PrincipalId ($servicePrincipal.objectId)
    
      Description
      -----------
      Assign two Azure AD roles to a service principal

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PrincipalId,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $RoleDefinitionId,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $RoleDefinitionDisplayName = $RoleDefinitionId
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        . "$PSScriptRoot/Invoke-Exe.ps1"

        $adRoleAssignmentUrl = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments'
        $adRoleAssignmentListUrl = '{0}?$filter = principalId eq ''{1}''' -f $adRoleAssignmentUrl, $PrincipalId

        $existingAssigments = Invoke-Exe { az rest --url $adRoleAssignmentListUrl } -EA SilentlyContinue | 
            ConvertFrom-Json | 
            Select-Object -ExpandProperty value | 
            Select-Object -ExpandProperty roleDefinitionId
        
    }
    process {
        try {
            if ($RoleDefinitionId -in $existingAssigments) {
                Write-Information "  Azure AD role '$RoleDefinitionDisplayName' already assigned to principal '$PrincipalId', skipping assignment"
            } else {
                $adRoleAssignmentJson = @{
                    '@odata.type'       = '#microsoft.graph.unifiedRoleAssignment'
                    principalId         = $PrincipalId
                    roleDefinitionId    = $RoleDefinitionId
                    directoryScopeId    = '/'
                } | ConvertTo-Json -Compress | ConvertTo-Json
                Write-Information "  Assigning Azure AD role '$RoleDefinitionDisplayName' to principal '$PrincipalId'..."
                Invoke-Exe { az rest --method post --url $adRoleAssignmentUrl --body $adRoleAssignmentJson } | Out-Null
            }
        } catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}