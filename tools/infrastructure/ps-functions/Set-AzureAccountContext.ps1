function Set-AzureAccountContext {
    <#
      .SYNOPSIS
      Set the account context so that Az powershell cmdlet's are authenticated to azure

      .PARAMETER Login
      Perform an interactive login to azure

      .PARAMETER SubscriptionId
      The Azure subscription to act on when setting the desired state of Azure resources. If not supplied, then the subscription
      already set as the current context will used (see Get-AzContext, Select-Subscription)
    #>
    [CmdletBinding()]
    param(
        [switch] $Login,
        [string] $SubscriptionId
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            if ($Login) {
                Write-Information 'Connecting to Azure AD Account...'

                if ($SubscriptionId) {
                    Write-Information "  Setting Subscripton context to $SubscriptionId"
                    Connect-AzAccount -Subscription $SubscriptionId -EA Stop | Out-Null
                } else {
                    Connect-AzAccount -EA Stop | Out-Null
                }

                # Also authenticate az CLI so both tools share the same identity. This opens a second
                # browser tab, but the existing SSO session from Connect-AzAccount means it typically
                # only requires a single click to confirm the account rather than full credential entry.
                $azCtxForLogin = Get-AzContext -EA Stop
                Write-Information '  Signing in to az CLI...'
                az login --tenant $azCtxForLogin.Tenant.Id --allow-no-subscriptions | Out-Null
            } elseif ($SubscriptionId) {
                Write-Information "Using existing sign-in context..."
                Write-Information "  Setting Subscripton context to $SubscriptionId"
                Select-AzSubscription -SubscriptionId $SubscriptionId -EA Stop | Out-Null
            }

            $currentAzContext = Get-AzContext -EA Stop
            if (-not($currentAzContext)) {
                throw 'There is no Azure Account context set. Please make sure to login using Connect-AzAccount'
            }
            Write-Information "Account context established"
            Write-Information "  INFO | TenantId: $($currentAzContext.Tenant)"
            Write-Information "  INFO | SubscriptionId: $($currentAzContext.Subscription)"

            # Sync the az CLI subscription to match the Az module context so both tools always
            # operate on the same subscription, regardless of how they were authenticated.
            az account set --subscription $currentAzContext.Subscription.Id
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}