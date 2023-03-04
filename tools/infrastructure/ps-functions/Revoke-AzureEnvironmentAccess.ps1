function Revoke-AzureEnvironmentAccess {
    <#
      .SYNOPSIS
      Revoke permissions to a user to access azure resources for product
      
      .PARAMETER InputObject
      The conventions describing the resource in a specific environment

      .PARAMETER UserPrincipalName
      The name of the user principal in azure to revoke permissions to

      .PARAMETER AccessLevel
      The access level to revoke (development, support-tier-1, support-tier-2)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject,
        
        [Parameter(Mandatory)]
        [string] $UserPrincipalName,

        [Parameter(Mandatory)]
        [ValidateSet('development', 'support-tier-1', 'support-tier-2')]
        [string] $AccessLevel
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

            $user = Get-AzAdUser -UserPrincipalName $UserPrincipalName
            if (-not($user)) {
                Write-Error "User not found; attempt to match on User Principal Name '$UserPrincipalName'"
            }

            $groupToRevoke = $InputObject | Resolve-TeamGroupName -AccessLevel $AccessLevel

            #------------- Remove RBAC permissions -------------
            $resourceGroupName = $InputObject.AppResourceGroup.ResourceName
            $rg = Get-AzResourceGroup $resourceGroupName
            
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
                Resolve-RbacRoleAssignment |
                Where-Object ObjectId -eq $user.Id
            $assignmentsToRevoke | Revoke-RbacRole -Scope $rg.ResourceId

            
            #------------- Remove from AAD group -------------
            $group = Get-AzAdGroup -DisplayName $groupToRevoke
            $groupMembership = $group | Get-AzADGroupMember | Where-Object Id -eq $user.Id
            if ($groupMembership) {
                Write-Information "Removing user '$UserPrincipalName' from group '$groupToRevoke'"
                $group | Remove-AzADGroupMember -MemberUserPrincipalName $UserPrincipalName -EA Stop
            }

            #------------- Summarize work -------------
            Write-Output "Permissions revoked from '$UserPrincipalName' (see tables below)"
            Write-Output 'RBAC Permissions'
            Write-Output '----------------'
            $assignmentsToRevoke | Select-Object *, @{ N='Scope'; E={ $resourceGroupName } } | Format-Table
            Write-Output 'Security Group Membership'
            Write-Output '-------------------------'
            if ($groupMembership) {
                $group | Select-Object DisplayName
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}