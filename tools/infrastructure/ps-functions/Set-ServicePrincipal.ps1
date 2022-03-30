function Set-ServicePrincipal {
    <#
      .SYNOPSIS
      Create/update an Azure service principal
      
      .DESCRIPTION
      Create/update an Azure service principal.
      This function is idempotent - roles already assigned to the service prinicpal will be skipped.
      Any existing roles that the principal is assigned that is not specified as argument values to the function
      call will NOT be removed
    
      .PARAMETER DisplayName
      The display name of the prinicpal that is to be created/updated
      
      .PARAMETER RbacRole
      One or more Azure RBAC roles to assign
      
      .PARAMETER ADRole
      One or more Azure AD roles to assign
      
      .PARAMETER NoPassword
      When creating the service principal, do NOT assign a client secret 

      .EXAMPLE
        $appParams = @{
            DisplayName     =   'automation-account'
            RbacRole        =   'Contributor', 'User Access Administrator'
            ADRole          =   @(
                @{
                    RoleDefinitionId            = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3'
                    RoleDefinitionDisplayName   = 'Application administrator'
                }
                @{
                    RoleDefinitionId            = 'fdd7a751-b60b-444a-984c-02652fe8fa1c'
                    RoleDefinitionDisplayName   = 'Groups administrator'
                }
                @{
                    RoleDefinitionId            = 'e8611ab8-c189-46e8-94e1-60213ab1f814'
                    RoleDefinitionDisplayName   = 'Privileged role administrator'
                }
            )
        }
        Set-ServicePrincipal @appParams
    
      Description
      -----------
      Create/update service principal and ensure this principal has the roles specified

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DisplayName,
        
        [string[]] $RbacRole = @(),
        
        [Hashtable[]] $ADRole = @(),
    
        [switch] $NoPassword
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/Grant-ADRole.ps1"
        . "$PSScriptRoot/Grant-RbacRole.ps1"
        . "$PSScriptRoot/Invoke-Exe.ps1"
    }
    process {
        try {
            Write-Information "Create/update service principal '$DisplayName'..."

            $servicePrincipal = Invoke-Exe {
                az ad sp list --display-name $DisplayName
            } | ConvertFrom-Json | Select-Object -First 1

            if ($servicePrincipal) {
                Write-Information "  Service principal found, skipping create"
            } else {
                Write-Information "  No service principal found. Creating now..."
                $servicePrincipal = Invoke-Exe { az ad sp create-for-rbac --name $DisplayName } | 
                    Tee-Object -Variable servicePrincipalOutput  | 
                    ConvertFrom-Json
                
                if ($NoPassword) {
                    $credential = Invoke-Exe {
                        az ad sp credential list --id $servicePrincipal.appId
                    } | ConvertFrom-Json | Select-Object -First 1
                    if ($credential) {
                        Write-Information "  Removing auto-generated client secret for service principal..."
                        Invoke-Exe {
                            az ad sp credential delete --id $servicePrincipal.appId --key-id $credential.keyId
                        } | Out-Null
                    }
                } else {
                    Write-Host $servicePrincipalOutput
                }

                # we need the objectId field which we don't get returned by `az ad sp create-for-rbac` above
                $servicePrincipal = Invoke-Exe { az ad sp show --id $servicePrincipal.appId } | ConvertFrom-Json
            }

            $RbacRole | Grant-RbacRole -PrincipalId ($servicePrincipal.objectId)
            $ADRole | ForEach-Object { [PsCustomObject]$_ } | Grant-ADRole -PrincipalId ($servicePrincipal.objectId)
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}