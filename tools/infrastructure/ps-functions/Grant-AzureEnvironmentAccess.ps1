function Grant-AzureEnvironmentAccess {
    <#
      .SYNOPSIS
      Grants access to Azure resources for a specific environment to a user according to the access level requested
      
      .PARAMETER InputObject
      The conventions describing the resource in a specific environment

      .PARAMETER UserPrincipalName
      The name of the user principal in azure to grant permissions to. If not supplied, then apply RBAC permissions
      to all existing users

      .PARAMETER AccessLevel
      The access level to grant (development, support-tier-1, support-tier-2)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject,
        
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
        . "$PSScriptRoot/Get-ResourceConvention.ps1"
        . "$PSScriptRoot/Grant-RbacRole.ps1"
        . "$PSScriptRoot/Resolve-RbacRoleAssignment.ps1"
        . "$PSScriptRoot/Resolve-TeamGroupName.ps1"
        . "$PSScriptRoot/Set-AADGroup.ps1"
    }
    process {
        try {
            
            $user = if ($UserPrincipalName) { Get-AzAdUser -UserPrincipalName $UserPrincipalName }
            $rbacUserFilter = if($user) {
                { $_.ObjectId -eq $user.Id }
            } else {
                { $true }
            }
            $groupMembers = if ($user) {
                @{
                    UserPrincipalName   =   $UserPrincipalName
                    Type                =   'User'
                }
            } else {
                @()
            }

            $groupName = $InputObject | Resolve-TeamGroupName -AccessLevel $AccessLevel

            #------------- Assign to AAD group -------------
            $group = [PsCustomObject]@{ Name = $groupName; Member = $groupMembers }
            $group | Set-AADGroup

            #------------- Set RBAC permissions -------------
            $resourceGroupName = $InputObject.AppResourceGroup.ResourceName
            $rg = Get-AzResourceGroup $resourceGroupName
            $roleAssignments = Get-RbacRoleAssignment $InputObject | Where-Object MemberName -eq $groupName

            if ($user) {
                $wait = 15
                Write-Information "Waitinng $wait secconds for group member assignment to be propogated before setting RBAC permissions"
                Start-Sleep -Seconds $wait
            }
            $roleAssignments |
                Resolve-RbacRoleAssignment |
                Where-Object $rbacUserFilter |
                Grant-RbacRole -Scope $rg.ResourceId
            

            #------------- Summarize work -------------
            $usersAffected = $user ? "'$UserPrincipalName'" : 'existing users'
            Write-Output "Permissions granted to $usersAffected (see tables below)"
            Write-Output 'RBAC Permissions'
            Write-Output '----------------'
            $roleAssignments | Select-Object MemberName, Role, @{ N='Scope'; E={ $resourceGroupName } } | Format-Table
            Write-Output 'Security Group Membership'
            Write-Output '-------------------------'
            $group | Select-Object Name
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}