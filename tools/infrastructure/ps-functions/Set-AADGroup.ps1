function Set-AADGroup {
    <#
      .SYNOPSIS
      Assign Azure Active Directory (AAD) a group with group membership
      
      .DESCRIPTION
      Assign Azure Active Directory (AAD) a group with group membership. The group members can be either 'User' or 'ServicePrincipal',
      and can include the current user logged in via Connect-AzAccount

      
      Required permission to run this script: 
      * Azure AD Groups administrator
    
      .PARAMETER Name
      The name of AAD Group to set
      
      .PARAMETER Member
      The list of users and/or service principals to set as members of this group
      
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
      Set-AADGroup my-group
    
      Description
      -----------
      Ensures the group 'my-group' is created in Azure AD

      .EXAMPLE
      Set-AADGroup my-group -Member @{
        ApplicationId           =   '96a99e94-acdc-41a0-ae6a-0836b968de57'
        Type                    =   'ServicePrincipal'
      }
    
      Description
      -----------
      Ensures the group 'my-group' is created in Azure AD and has the service principal as a member

      .EXAMPLE
      Set-AADGroup my-group -Member @{
        ApplicationId           =   'kc.mriazure_gmail.com#EXT#@kcmriazuregmail.onmicrosoft.com'
        Type                    =   'User'
      }
    
      Description
      -----------
      Ensures the group 'my-group' is created in Azure AD and has the Azure AD User as a member

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
              UserPrincipalName   =   'kc.mriazure_gmail.com#EXT#@kcmriazuregmail.onmicrosoft.com'
              Type                =   'User'
            }
          )
          IncludeCurrentUser  =   $true
        }
      )
      $groups | Set-AADGroup
    
      Description
      -----------
      Ensures the group 'my-group' and 'my-other-group' is created in Azure AD along with the supplied group membership

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $Name,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Hashtable[]] $Member = @(),

        [Parameter(ValueFromPipelineByPropertyName)]
        [switch] $IncludeCurrentUser
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        . "$PSScriptRoot/Invoke-EnsureHttpSuccess.ps1"

        Write-Verbose "Current signed-in account type: '$($currentAzContext.Account.Type)'"
    }
    process {
        try {

            $currentAzContext = Get-AzContext -EA Stop
            if (-not($currentAzContext)) {
                throw 'There is no Azure Account context set. Please make sure to login using Connect-AzAccount'
            }

            $servicePrincipals = $Member | Where-Object Type -eq 'ServicePrincipal'
            $users = $Member | Where-Object { $_ -notin $servicePrincipals }
            
            $servicePrincipals = if ($IncludeCurrentUser -and $currentAzContext.Account.Type -in 'ServicePrincipal', 'ClientAssertion') {
                Write-Verbose "Adding current signed-in service principal account to member list for group '$($currentAzContext.Account.Type)'"
                $servicePrincipals
                @{
                    ApplicationId   =   $currentAzContext.Account.Id
                }
            } else {
                $servicePrincipals
            }

            $users = if ($IncludeCurrentUser -and $currentAzContext.Account.Type -eq 'User') {
                Write-Verbose "Adding current signed-in user account to member list for group '$($currentAzContext.Account.Type)'"
                $users
                @{
                    UserPrincipalName  =   (Get-AzADUser -SignedIn -EA Stop).UserPrincipalName
                }
            }
            else {
                $users
            }

            Write-Information "Searching for Azure AD group '$Name'..."
            $group = Get-AzADGroup -DisplayName $Name -EA Stop
            $groupNotFound = $null -eq $group
            if ($groupNotFound) {
                Write-Information "  Group not found. Creating..."
                $group = New-AzADGroup -DisplayName $Name -MailNickname $Name -EA Stop
            } else {
                Write-Information "  Group already exists. Skipping create"
            }
            
            if (($users -or $servicePrincipals) -and $groupNotFound) {
                $wait = 15
                Write-Information "Waitinng $wait secconds for new group record to be propogated before assigning members"
                Start-Sleep -Seconds 15
            }

            if ($users) {
                Write-Information "Searching for user group membership of Azure AD group '$Name'..."
                $existingUsers = $group |
                    Get-AzADGroupMember -EA Stop |
                    ForEach-Object { Get-AzADUser -ObjectId ($_.Id) } |
                    Select-Object -ExpandProperty UserPrincipalName
                $requiredUsers = $users | Select-Object -ExpandProperty UserPrincipalName | Select-Object -Unique
                $missingUsers = $requiredUsers | Where-Object { $_ -notin $existingUsers }
                if ($missingUsers) {
                    Write-Information "  Adding additional group members..."
                    Add-AzADGroupMember -TargetGroupObjectId ($group.Id) -MemberUserPrincipalName $missingUsers -EA Stop | Out-Null
                }
            }

            if ($servicePrincipals) {
                # Note: we're using Invoke-AzRestMethod to get service principal membership because Get-AzADGroupMember
                # currently does not return service principals. Once it does replace with Get-AzADGroupMember
                Write-Information "Searching for service principal group membership of Azure AD group '$Name'..."
                $nameMembersUrl = "https://graph.microsoft.com/beta/groups/$( $group.Id )/members"
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
                    Add-AzADGroupMember -TargetGroupObjectId ($group.Id) -MemberObjectId ($missingServicePrincipals.Id) -EA Stop
                }
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}