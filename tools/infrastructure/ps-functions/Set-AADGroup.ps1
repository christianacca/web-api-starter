function Set-AADGroup {
    <#
      .SYNOPSIS
      Assign Azure Active Directory (AAD) group with group membership and/or ownership
      
      .DESCRIPTION
      Assign Azure Active Directory (AAD) group with group membership and/or ownership.
      The group members can be either 'User', 'Group' or 'ServicePrincipal', and can include the current user logged in via Connect-AzAccount
      The group owners can be either 'User' or 'ServicePrincipal'

      
      Required permission to run this script: 
      * Azure AD permission: microsoft.directory/groups.security/createAsOwner
    
      .PARAMETER Name
      The name of AAD Group to set
      
      .PARAMETER Member
      The list of users, groups and service principals to set as members of this group
      
      .PARAMETER Owner
      The list of users and/or service principals to set as owners of this group
      
      .PARAMETER IncludeCurrentUser
      Whether to set the current logged in user as a member of this group. To loggin use Connect-AzConnect

      .EXAMPLE
      Set-AADGroup my-group
    
      Description
      -----------
      Ensures the group 'my-group' is created in Azure AD

      .EXAMPLE
      Set-AADGroup my-group -IncludeCurrentUser
    
      Description
      -----------
      Ensures the group 'my-group' is created in Azure AD and has the current logged in user/service princial as a member

      .EXAMPLE
      Set-AADGroup my-group -Member @{
        ApplicationId           =   '96a99e94-acdc-41a0-ae6a-0836b968de57'
        Type                    =   'ServicePrincipal'
      }
    
      Description
      -----------
      Ensures the group 'my-group' is created in Azure AD and has the service principal as a member

      .EXAMPLE
      'my-group1', 'my-group2' | Set-AADGroup -Member @{
        ApplicationId           =   '96a99e94-acdc-41a0-ae6a-0836b968de57'
        Type                    =   'ServicePrincipal'
      }
    
      Description
      -----------
      Ensures the group 'my-group1' and 'my-group2' is created in Azure AD and has the service principal as a member

      .EXAMPLE
      Set-AADGroup my-group -Member @{
        UserPrincipalName       =   'kc.mriazure_gmail.com#EXT#@kcmriazuregmail.onmicrosoft.com'
        Type                    =   'User'
      }
    
      Description
      -----------
      Ensures the group 'my-group' is created in Azure AD and has the Azure AD User as a member

      .EXAMPLE
      Set-AADGroup my-group -Owner @{
        UserPrincipalName       =   'kc.mriazure_gmail.com#EXT#@kcmriazuregmail.onmicrosoft.com'
        Type                    =   'User'
      }
    
      Description
      -----------
      Ensures the group 'my-group' is created in Azure AD and has the Azure AD User as a owner

      .EXAMPLE
      $groups = @(
        [PsCustomObject]@{
          Name                =   'my-group'
          IncludeCurrentUser  =   $true
        }
        [PsCustomObject]@{  
          Name                =   'my-other-group'
          Member              = @(
            @{
              ApplicationId       =   '96a99e94-acdc-41a0-ae6a-0836b968de57'
              Type                =   'ServicePrincipal'
            }
            @{
              Name                =   'sg.365.pbi.workspace.aig.dev.app'
              Type                =   'Group'
            }
            @{
              UserPrincipalName   =   'kc.mriazure_gmail.com#EXT#@kcmriazuregmail.onmicrosoft.com'
              Type                =   'User'
            }
          )
          Owner               = @(
            @{
              ApplicationId       =   'e7bac8c3-c4f5-437a-beec-f3d5ce1dd14a'
              Type                =   'ServicePrincipal'
            }
            @{
              UserPrincipalName   =   'christian.crowhurst@mrisoftware.com'
              Type                =   'User'
            }
          )
          IncludeCurrentUser  =   $true
        }
      )
      $groups | Set-AADGroup
    
      Description
      -----------
      Ensures the group 'my-group' and 'my-other-group' is created in Azure AD along with the supplied group membership and ownership

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ValueFromPipeline)]
        [string] $Name,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Hashtable[]] $Member = @(),

        [Parameter(ValueFromPipelineByPropertyName)]
        [Hashtable[]] $Owner = @(),

        [Parameter(ValueFromPipelineByPropertyName)]
        [switch] $IncludeCurrentUser
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        . "$PSScriptRoot/Get-CurrentUserAsMember.ps1"
        . "$PSScriptRoot/Invoke-EnsureHttpSuccess.ps1"
    }
    process {
        try {            
            if ($IncludeCurrentUser) {
                $currentUserMember = Get-CurrentUserAsMember
                $Member = @($currentUserMember; $Member)
                Write-Verbose "Adding current signed-in $($currentUserMember.Type) to member list for group '$Name'"
            }

            $servicePrincipals = $Member | Where-Object Type -eq 'ServicePrincipal'
            $users = $Member | Where-Object Type -eq 'User'
            $groups = $Member | Where-Object Type -eq 'Group'
            

            Write-Information "Searching for Azure AD group '$Name'..."
            $group = Get-AzADGroup -DisplayName $Name -EA Stop
            $groupNotFound = $null -eq $group
            if ($groupNotFound) {
                Write-Information "  Group not found. Creating..."
                $group = New-AzADGroup -DisplayName $Name -MailNickname $Name -EA Stop
            } else {
                Write-Information "  Group already exists. Skipping create"
            }
            
            if (($users -or $servicePrincipals -or $groups -or $Owner) -and $groupNotFound) {
                $wait = 15
                Write-Information "Waitinng $wait secconds for new group record to be propogated before assigning members"
                Start-Sleep -Seconds $wait
            }

            $servicePrincipalsOwners = $Owner | Where-Object Type -eq 'ServicePrincipal'
            $userOwners = $Owner | Where-Object { $_ -notin $servicePrincipals }

            if ($userOwners) {
                Write-Information "Searching for user group ownership of Azure AD group '$Name'..."
                $existingUserOwners = { Invoke-AzRestMethod -Uri "https://graph.microsoft.com/beta/groups/$($group.Id)/owners" -EA Stop } |
                    Invoke-EnsureHttpSuccess |
                    ConvertFrom-Json |
                    Select-Object -ExpandProperty value |
                    Where-Object '@odata.type' -eq '#microsoft.graph.user' |
                    Select-Object -ExpandProperty UserPrincipalName
                $requiredUserOwners = $userOwners | Select-Object -ExpandProperty UserPrincipalName | Select-Object -Unique
                $missingUserOwners = $requiredUserOwners |
                    Where-Object { $_ -notin $existingUserOwners } |
                    ForEach-Object { Get-AzADUser -UserPrincipalName $_ -EA Stop }
                if ($missingUserOwners) {
                    $missingUserOwners | ForEach-Object {
                        Write-Information "  Adding additional user group owner '$($_.UserPrincipalName)'..."
                        $payload = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($_.Id)" } | ConvertTo-Json -Compress
                        $addOwnerUrl = $('https://graph.microsoft.com/v1.0/groups/' + $group.Id + '/owners/$ref')
                        { Invoke-AzRestMethod -Method POST $addOwnerUrl -Payload $payload } | Invoke-EnsureHttpSuccess | Out-Null
                    }
                }
            }

            if ($servicePrincipalsOwners) {
                Write-Information "Searching for service principal group ownership of Azure AD group '$Name'..."
                $existingSpOwners = { Invoke-AzRestMethod -Uri "https://graph.microsoft.com/beta/groups/$($group.Id)/owners" -EA Stop } |
                    Invoke-EnsureHttpSuccess |
                    ConvertFrom-Json |
                    Select-Object -ExpandProperty value |
                    Where-Object '@odata.type' -eq '#microsoft.graph.servicePrincipal' |
                    Select-Object -ExpandProperty AppId
                $requiredSpOwners = $servicePrincipalsOwners | Select-Object -ExpandProperty ApplicationId | Select-Object -Unique
                $missingSpOwners = $requiredSpOwners |
                    Where-Object { $_ -notin $existingSpOwners } |
                    ForEach-Object { Get-AzADServicePrincipal -ApplicationId $_ -EA Stop }
                if ($missingSpOwners) {
                    $missingSpOwners | ForEach-Object {
                        Write-Information "  Adding additional service principal group owner '$($_.AppId)'..."
                        $payload = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/serviceprincipals/$($_.Id)" } | ConvertTo-Json -Compress
                        $addOwnerUrl = $('https://graph.microsoft.com/v1.0/groups/' + $group.Id + '/owners/$ref')
                        { Invoke-AzRestMethod -Method POST $addOwnerUrl -Payload $payload } | Invoke-EnsureHttpSuccess | Out-Null
                    }
                }
            }
            
            if ($users) {
                Write-Information "Searching for user group membership of Azure AD group '$Name'..."
                $existingUsers = $group |
                    Get-AzADGroupMember -EA Stop |
                    Where-Object OdataType -eq '#microsoft.graph.user' |
                    ForEach-Object { Get-AzADUser -ObjectId ($_.Id) } |
                    Select-Object -ExpandProperty UserPrincipalName
                $requiredUsers = $users | Select-Object -ExpandProperty UserPrincipalName | Select-Object -Unique
                $missingUsers = $requiredUsers | Where-Object { $_ -notin $existingUsers }
                if ($missingUsers) {
                    Write-Information "  Adding additional group members..."
                    $escapedUserNames = $missingUsers | ForEach-Object { $_.Replace("'", "''") }
                    Add-AzADGroupMember -TargetGroupObjectId ($group.Id) -MemberUserPrincipalName $escapedUserNames -EA Stop | Out-Null
                }
            }   
            
            if ($groups) {
                Write-Information "Searching for group membership of Azure AD group '$Name'..."
                $existingGroups = $group |
                    Get-AzADGroupMember -EA Stop |
                    Where-Object OdataType -eq '#microsoft.graph.group' |
                    ForEach-Object { Get-AzADGroup -ObjectId ($_.Id) } |
                    Select-Object -ExpandProperty DisplayName
                $requiredGroups = $groups | Select-Object -ExpandProperty Name | Select-Object -Unique
                $missingGroups = $requiredGroups |
                    Where-Object { $_ -notin $existingGroups } |
                    ForEach-Object { Get-AzADGroup -DisplayName $_ } |
                    Select-Object -ExpandProperty Id
                if ($missingGroups) {
                    Write-Information "  Adding additional groups as group members..."
                    Add-AzADGroupMember -TargetGroupObjectId ($group.Id) -MemberObjectId $missingGroups -EA Stop | Out-Null
                }
            }

            if ($servicePrincipals) {
                # Note: we're using Invoke-AzRestMethod to get service principal membership because Get-AzADGroupMember
                # currently does not return service principals. Once it does replace with Get-AzADGroupMember
                Write-Information "Searching for service principal group membership of Azure AD group '$Name'..."
                $nameMembersUrl = "https://graph.microsoft.com/beta/groups/$($group.Id)/members"
                $existingServicePrincipals = { Invoke-AzRestMethod -Uri $nameMembersUrl -EA Stop } |
                    Invoke-EnsureHttpSuccess |
                    ConvertFrom-Json |
                    Select-Object -ExpandProperty value |
                    Select-Object -Property DisplayName, Id, @{ label = 'OdataType'; expression = { $_.'@odata.type' } }, AppId |
                    Where-Object OdataType -eq '#microsoft.graph.servicePrincipal' |
                    Select-Object -ExpandProperty AppId

                $requiredServicePrincipals = $servicePrincipals |
                    Select-Object -ExpandProperty ApplicationId |
                    Select-Object -Unique | 
                    ForEach-Object { Get-AzADServicePrincipal -ApplicationId $_ -EA Stop }
                $missingServicePrincipals = $requiredServicePrincipals | Where-Object AppId -notin $existingServicePrincipals

                if ($missingServicePrincipals) {
                    Write-Information "  Adding service principal(s) to group..."
                    Add-AzADGroupMember -TargetGroupObjectId ($group.Id) -MemberObjectId ($missingServicePrincipals.Id) -EA Stop | Out-Null
                }
            }

            $group
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}