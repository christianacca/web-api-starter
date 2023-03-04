function Get-CurrentUserAsMember {
    [CmdletBinding()]
    param()
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            $currentAzContext = Get-AzContext -EA Stop
            if (-not($currentAzContext)) {
                throw 'Cannot return Member record as there is no Azure Account context set. Please make sure to login using Connect-AzAccount'
            }
            
            if ($currentAzContext.Account.Type -in 'ServicePrincipal', 'ClientAssertion') {
                @{
                    ApplicationId   =   $currentAzContext.Account.Id
                    Type            =   'ServicePrincipal'
                }
            } else {
                @{
                    UserPrincipalName   =   (Get-AzADUser -SignedIn -EA Stop).UserPrincipalName
                    Type                =   'User'
                }
            }
        } 
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
