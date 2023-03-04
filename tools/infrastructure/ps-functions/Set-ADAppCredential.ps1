function Set-ADAppCredential {
    <#
      .SYNOPSIS
      Creates a client secret associated with an AD application, recreating the existing client secret if it has expired
      
      .DESCRIPTION
      Creates a client secret associated with an AD application, recreating the existing client secret if it has expired
      This script is written to be idempotent so it is safe to be run multiple times.
      
      Required permission to run this script:
      * Azure AD role: 'Application developer'
    
      .PARAMETER InputObject
      The Application returned by Get-AzADApplication to which to set client credential
    
      .PARAMETER DisplayName
      The Display name of the client secret. Defaults to the DisplayName of the application suffixed '-pswd1'
    
      .PARAMETER ExpiryInDays
      The number of days that the client secret will expire

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $InputObject,
    
        [string] $DisplayName,
    
        [int] $ExpiryInDays = 60
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        function New-Password {
            $password = New-Object Microsoft.Azure.PowerShell.Cmdlets.Resources.MSGraph.Models.ApiV10.MicrosoftGraphPasswordCredential
            # todo: set EndDate to 3 months from now
            $password.DisplayName = $DisplayName
            $password.EndDateTime = (Get-Date).AddDays($ExpiryInDays)
            $InputObject | New-AzADAppCredential -PasswordCredentials $password -EA Stop
        }
    }
    process {
        try {

            if (-not($DisplayName)) {
                $DisplayName = "$($InputObject.DisplayName)-pswd1"
            }
            
            Write-Information "Searching for existing Azure AD App client secret '$DisplayName'..."
            $credential = $InputObject | Get-AzADAppCredential -EA Stop | Where-Object DisplayName -eq $DisplayName
            if (-not($credential)) {
                Write-Information "  Existing AD App credential not found. Creating..."
                $credential = New-Password
            } else {
                Write-Information "  Existing AD App credential found. Skipping create"
                $currentDate = Get-Date
                if ($credential.EndDateTime -lt $currentDate) {
                    Write-Information "  Existing AD App credential has expired. Re-creating password with the same name"
                    $InputObject | Remove-AzADAppCredential -KeyId $credential.KeyId -EA Stop | Out-Null
                    $credential = New-Password
                }
            }

            $credential
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
