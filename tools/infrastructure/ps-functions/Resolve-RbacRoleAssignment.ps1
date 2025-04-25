function Resolve-RbacRoleAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $Role,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $MemberName,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $MemberType,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $Scope,
    
        [switch] $ExpandGroupMembership
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        Write-Information "Resolving identities for RBAC role assignments"

        $roleAssignmants = @()
    }
    process {
        $roleAssignmants = @(
            @{
                MemberName  =   $MemberName
                MemberType  =   $MemberType
                Role        =   $Role
                Scope       =   $Scope
            }
        ) + $roleAssignmants

        $membershipByGroupName = @{}
    }
    end {
        try {
            $roleAssignmants | ForEach-Object {
                $role = $_.Role
                $scope = $_.Scope
                if ($_.MemberType -eq 'Group' -and $ExpandGroupMembership) {
                    
                    if (-not($membershipByGroupName.ContainsKey($_.MemberName))) {
                        $membershipByGroupName[$_.MemberName] = Get-AzADGroup -DisplayName $_.MemberName -EA Stop | Get-AzADGroupMember -EA Stop
                    }
                    $membership = $membershipByGroupName[$_.MemberName]

                    $membership | ForEach-Object {
                        [PsCustomObject]@{
                            ObjectId            =   $_.Id
                            RoleDefinitionName  =   $role
                            Scope               =   $scope
                        }
                    }
                } elseif ($_.MemberType -eq 'Group' -and -not($ExpandGroupMembership)) {
                    [PsCustomObject]@{
                        ObjectId                =   (Get-AzADGroup -DisplayName $_.MemberName -EA Stop).Id
                        RoleDefinitionName      =   $role
                        Scope                   =   $scope
                    }
                } elseif ($_.MemberType -eq 'User') {
                    [PsCustomObject]@{
                        ObjectId                =   (Get-AzADUser -UserPrincipalName $_.MemberName -EA Stop).Id
                        RoleDefinitionName      =   $role
                        Scope                   =   $scope
                    }
                } elseif ($_.MemberType -eq 'ServicePrincipal') {
                    [PsCustomObject]@{
                        ObjectId                =   (Get-AzADServicePrincipal -ApplicationId $_.MemberName).Id
                        RoleDefinitionName      =   $role
                        Scope                   =   $scope
                    }
                }
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
