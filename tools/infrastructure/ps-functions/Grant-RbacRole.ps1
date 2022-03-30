function Grant-RbacRole {
    <#
      .SYNOPSIS
      Assign Azure RBAC role(s) to a principal
      
      .DESCRIPTION
      Assign Azure RBAC role(s) to a principal.
      This function is idempotent - any roles already assigned to the prinicpal will be skipped.
    
      .PARAMETER PrincipalId
      The ID of the prinicpal that is to be assigned the role(s)
      
      .PARAMETER PrincipalType
      The type of the principal
      
      .PARAMETER RoleName
      One or more roles to assign

      .EXAMPLE
      'Contributor', 'User Access Administrator' | Grant-RbacRole -PrincipalId ($servicePrincipal.objectId)
    
      Description
      -----------
      Assign two Azure RBAC roles to a service principal

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PrincipalId,

        [ValidateSet('ForeignGroup', 'Group', 'ServicePrincipal', 'User')]
        [string] $PrincipalType = 'ServicePrincipal',

        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]] $RoleName
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        . "$PSScriptRoot/Invoke-Exe.ps1"
    }
    process {
        try {
            $RoleName | ForEach-Object {
                $name = $_
                Write-Information "  Assigning RBAC role '$name' to service principal '$PrincipalId'..."
                Invoke-Exe {
                    az role assignment create --role $name --assignee-object-id  $PrincipalId --assignee-principal-type $PrincipalType
                } | Out-Null
            }
        } catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}