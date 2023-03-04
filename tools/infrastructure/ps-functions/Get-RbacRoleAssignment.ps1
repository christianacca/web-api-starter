function Get-RbacRoleAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias('Convention')]
        [Hashtable] $InputObject
    )

    $rbacAssignments = @(
        $InputObject.AppResourceGroup.RbacAssignment
        if ($InputObject.AppResourceGroup -ne $InputObject.DataResourceGroup) { $InputObject.DataResourceGroup.RbacAssignment }
        $InputObject.SubProducts.Values.RbacAssignment
    )
    
    $flattenedAssignments = $rbacAssignments  | ForEach-Object {
        $roles = $_.Role
        $members = $_.Member
        $roles | ForEach-Object {
            $role = $_
            $members | ForEach-Object {
                $member = $_
                $memberName = switch ($member.Type) {
                    'Group' {
                        $member.Name
                    }
                    'User' {
                        $member.UserPrincipalName
                    }
                    'ServicePrincipal' {
                        $member.ApplicationId
                    }
                    Default {
                        'UNKNOWN'
                    }
                }
                [PsCustomObject]@{
                    MemberName      = $memberName
                    MemberType      = $_.Type
                    Role            = $role
                }
            }
        }
    } | Sort-Object MemberName

    $flattenedAssignments
}
