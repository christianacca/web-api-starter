function Remove-RBACRoleFromManagedIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $ManagedIdentityResourceGroup,

        [string] $ResourceGroupScope = $ManagedIdentityResourceGroup
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/Invoke-Exe.ps1"
    }
    process {
        try {
            Write-Information "Removing all RBAC role assignments scoped to the resource group '$ResourceGroupScope' from managed identity '$Name'..."
            
            $managedIdentityClientId = Invoke-Exe {
                az identity show -g $ManagedIdentityResourceGroup -n $Name --query clientId -otsv
            }
            Invoke-Exe {
                az role assignment delete --assignee $managedIdentityClientId --resource-group $ResourceGroupScope
            }  | Out-Null
        }
        catch
        {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}