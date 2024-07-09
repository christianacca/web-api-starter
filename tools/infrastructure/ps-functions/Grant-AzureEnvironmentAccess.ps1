function Grant-AzureEnvironmentAccess {
    <#
      .SYNOPSIS
      Grants access to Azure resources for a specific environment to a user according to the access level requested
      
      .PARAMETER InputObject
      The conventions describing the resource in a specific environment

      .PARAMETER UserPrincipalName
      The name(s) of the user principal in azure to grant permissions to (via group membership).

      .PARAMETER AccessLevel
      The access level to grant (eg development). Note: 'GPS / support-tier-1' is an alias of 'support-tier-1'
      and 'App Admin / support-tier-2' is an alias of 'support-tier-2'

      .PARAMETER $SubProductName
      The name of the sub product to grant access

      .PARAMETER ApplyCurrentPermissions
      Apply the current desired permissions to existing Azure resources
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject,
        
        [string[]] $UserPrincipalName,

        [Parameter(Mandatory)]
        [ValidateSet('development', 'support-tier-1', 'support-tier-2', 'GPS / support-tier-1', 'App Admin / support-tier-2')]
        [string] $AccessLevel,
        
        [string] $SubProductName,
    
        [switch] $ApplyCurrentPermissions
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

            $userNames = $UserPrincipalName | Where-Object { $_ }
            $users = $userNames | ForEach-Object { Get-AzAdUser -UserPrincipalName $_.Replace("'", "''") }
            $notFound =  $userNames | Where-Object { $_ -notin $users.UserPrincipalName }
            if ($notFound) {
                throw "Cannot grant permissions, the following user principal names supplied were not found in Azure AD tenant: $notFound"    
            }
            
            $groupMembers = $users | ForEach-Object {
                @{
                    UserPrincipalName   =   $userNames
                    Type                =   'User'
                }
            }

            $groupName = $InputObject | Resolve-TeamGroupName -AccessLevel $AccessLevel -SubProductName $SubProductName

            #------------- Assign to AAD group -------------
            $group = [PsCustomObject]@{ Name = $groupName; Member = $groupMembers }
            $group | Set-AADGroup | Out-Null

            #------------- Set RBAC permissions -------------
            $resourceGroupName = $InputObject.AppResourceGroup.ResourceName
            $rg = Get-AzResourceGroup $resourceGroupName
            $roleAssignments = Get-RbacRoleAssignment $InputObject | Where-Object MemberName -eq $groupName

            if ($ApplyCurrentPermissions) {
                $roleAssignments |
                    Resolve-RbacRoleAssignment |
                    Grant-RbacRole -Scope $rg.ResourceId    
            }

            #------------- Summarize work -------------
            if ($ApplyCurrentPermissions) {
                Write-Output 'RBAC permissions have been reapplied to current Azure resources (see table below)'
            } else {
                Write-Output "Permissions granted to '$userNames' (see tables below)"
            }

            Write-Output 'RBAC Permissions'
            Write-Output '----------------'
            $roleAssignments | Select-Object MemberName, Role, @{ N='Scope'; E={ $resourceGroupName } } | Format-Table

            if ($users) {
                Write-Output 'Security Group Membership'
                Write-Output '-------------------------'
                $group | Select-Object Name    
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}