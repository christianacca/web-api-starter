    [CmdletBinding()]
    param(
        [string] $PrincipalName = 'automation-principal',
        [switch] $Login,
        [string] $SubscriptionId
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/ps-functions/Set-ServicePrincipal.ps1"
    }
    process {
        try {

            if ($Login.IsPresent) {
                Write-Information 'Connecting to Azure AD Account...'
                Invoke-Exe { az login } | Out-Null
            }
            if ($SubscriptionId) { 
                Invoke-Exe { az account set --subscription $SubscriptionId } | Out-Null
            }
            
            $appParams = @{
                DisplayName     =   $PrincipalName
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
            
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
