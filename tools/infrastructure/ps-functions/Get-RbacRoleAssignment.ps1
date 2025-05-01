<#
    .SYNOPSIS
    This function retrieves all Azure RBAC role assignments given the set of conventions for a specific environment
    
    .EXAMPLE
    . ./tools/infrastructure/ps-functions/Get-RbacRoleAssignment.ps1
    $convention = & "tools/infrastructure/get-product-conventions.ps1" -EnvironmentName dev -AsHashtable
    $convention | Get-RbacRoleAssignment | Sort-Object MemberName,MemberType,Scope | Format-List Role,Scope -GroupBy @{ n='MemberName|Type'; e={ '{0}|{1}' -f $_.MemberName, $_.MemberType } }
    
    Description
    -----------
    Returns the Azure RBAC role assignments for the dev environment, grouping the results by member name and type, and then outputting the result as a list.
#>


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
        $InputObject.TlsCertificates.Current.KeyVault.RbacAssignment
        $InputObject.ConfigStores.IsDeployed ? $InputObject.ConfigStores.Current.RbacAssignment : @()
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
