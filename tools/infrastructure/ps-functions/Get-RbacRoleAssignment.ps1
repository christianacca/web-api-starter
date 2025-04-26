function Get-RbacRoleAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias('Convention')]
        [Hashtable] $InputObject
    )

    $rbacAssignments = @(
        $InputObject.AppResourceGroup.RbacAssignment
        $InputObject.SubProducts.Values.RbacAssignment
        $InputObject.TlsCertificates.Dev.KeyVault.RbacAssignment
        $InputObject.TlsCertificates.Prod.KeyVault.RbacAssignment
        $InputObject.ConfigStores.IsDeployed ? @(
            $InputObject.ConfigStores.Dev.RbacAssignment
            $InputObject.ConfigStores.Prod.RbacAssignment
        ) : @()
    )
    
    $flattenedAssignments = $rbacAssignments  | ForEach-Object {
        $roles = $_.Role
        $members = $_.Member
        $scope = $_['Scope'] ?? $InputObject.AppResourceGroup.ResourceId
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
                    MemberType      = $member.Type
                    Role            = $role
                    Scope           = $scope
                }
            }
        }
    } | Sort-Object MemberName,Scope,MemberType,Role -Unique

    $flattenedAssignments
}
