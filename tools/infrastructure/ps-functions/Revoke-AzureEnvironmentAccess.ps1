function Revoke-AzureEnvironmentAccess {
    <#
      .SYNOPSIS
      Revoke permissions to a user to access azure resources for product
      
      .PARAMETER InputObject
      The conventions describing the resource in a specific environment

      .PARAMETER UserPrincipalName
      The name(s) of the user principal in azure to revoke permissions.

      .PARAMETER AccessLevel
      The access level to revoke (eg development). Note: 'GPS / support-tier-1' is an alias of 'support-tier-1'
      and 'App Admin / support-tier-2' is an alias of 'support-tier-2'

      .PARAMETER $SubProductName
      The name of the sub product to revoke access
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject,
        
        [Parameter(Mandatory)]
        [string[]] $UserPrincipalName,

        [Parameter(Mandatory)]
        [ValidateSet('development', 'support-tier-1', 'support-tier-2', 'GPS / support-tier-1', 'App Admin / support-tier-2')]
        [string] $AccessLevel,
        
        [string] $SubProductName
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/Get-RbacRoleAssignment.ps1"
        . "$PSScriptRoot/Revoke-RbacRole.ps1"
        . "$PSScriptRoot/Resolve-RbacRoleAssignment.ps1"
        . "$PSScriptRoot/Resolve-TeamGroupName.ps1"
    }
    process {
        try {

            $userNames = $UserPrincipalName | Where-Object { $_ }
            $users = $userNames | ForEach-Object { Get-AzAdUser -UserPrincipalName $_ }
            $notFound =  $userNames | Where-Object { $_ -notin $users.UserPrincipalName }
            if ($notFound) {
                throw "Cannot revoke permissions, the following user principal names supplied were not found in Azure AD tenant: $notFound"
            }

            $groupToRevoke = $InputObject | Resolve-TeamGroupName -AccessLevel $AccessLevel -SubProductName $SubProductName
            $group = Get-AzAdGroup -DisplayName $groupToRevoke -EA Stop
            $resourceGroupName = $InputObject.AppResourceGroup.ResourceName

            $users | ForEach-Object {
                $user = $_

                #------------- Calculate RBAC permissions that will be revoked -------------
                $allRoleAssignments = Get-RbacRoleAssignment $InputObject
                $allowedGroupNames = $allRoleAssignments |
                        Where-Object { $_.MemberType -eq 'Group' -and $_.MemberName -ne $groupToRevoke } |
                        Select-Object -ExpandProperty MemberName -Unique
                $assignedGroupNames = $allowedGroupNames |
                        Where-Object { Get-AzAdGroup -DisplayName $_ | Get-AzADGroupMember | Where-Object Id -eq $user.Id }
                $allowedRoles = $allRoleAssignments |
                        Where-Object MemberName -in $assignedGroupNames |
                        Select-Object -ExpandProperty Role -Unique

                $assignmentsToRevoke = $allRoleAssignments |
                        Where-Object { $_.MemberName -eq $groupToRevoke -and $_.Role -notin $allowedRoles } |
                        Resolve-RbacRoleAssignment -ExpandGroupMembership |
                        Where-Object ObjectId -eq $user.Id


                #------------- Remove from AAD group -------------
                # note: this will implicitly revoke the RBAC permissions calculated above
                
                $groupMembership = $group | Get-AzADGroupMember | Where-Object Id -eq $user.Id
                if ($groupMembership) {
                    Write-Information "Removing user '$($user.UserPrincipalName)' from group '$groupToRevoke'"
                    $group | Remove-AzADGroupMember -MemberUserPrincipalName $user.UserPrincipalName -EA Stop
                }

                #------------- Summarize work -------------
                Write-Output "Permissions revoked from '$($user.UserPrincipalName)' (see tables below)"
                Write-Output 'RBAC Permissions'
                Write-Output '----------------'
                $assignmentsToRevoke | Select-Object *, @{ N='Scope'; E={ $resourceGroupName } } | Format-Table
                Write-Output 'Security Group Membership'
                Write-Output '-------------------------'
                if ($groupMembership) {
                    $group | Select-Object DisplayName
                }
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}