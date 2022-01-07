function Remove-ADAppRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $DiplayName
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/Invoke-Exe.ps1"
    }
    process {
        try {
            Write-Information "Remove Azure AD app registration '$DiplayName'..."
            
            $adRegistration = Invoke-Exe {
                az ad app list --display-name $DiplayName
            } | ConvertFrom-Json | Select-Object -First 1
            
            if ($adRegistration) {
                Write-Information "  AD app registration found, deleting now..."
                $servicePrincipalId = Invoke-Exe {
                    az ad sp show --id ($adRegistration.appId) --query objectId -otsv
                } -EA SilentlyContinue

                if ($servicePrincipalId) {
                    # removing the service principal also removes the app registration
                    Invoke-Exe { az ad sp delete --id $servicePrincipalId }
                }
            } else {
                Write-Information "  No AD app registration found"
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}