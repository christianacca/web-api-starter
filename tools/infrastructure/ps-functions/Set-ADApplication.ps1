function Set-ADApplication {
    <#
      .SYNOPSIS
      Creates the AD application with associated service principal
      
      .DESCRIPTION
      Creates the AD application with associated service principal.
      This script is written to be idempotent so it is safe to be run multiple times.
      
      Required permission to run this script:
      * Azure AD role: 'Application developer'
    
      .PARAMETER InputObject
      Hashtable containing the parameters to create the AD application. At minimum this needs to include `DisplayName`

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Hashtable] $InputObject
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        $name = $InputObject['DisplayName']

    }
    process {
        try {
            if (-not($name)) {
                throw 'DisplayName is required to be supplied as part of InputObject argument'
            }

            Write-Information "Searching for existing Azure AD App registration '$name'..."
            $appRegistration = Get-AzADApplication -DisplayName $name -EA Stop
            if (-not($appRegistration)) {
                Write-Information "  Existing AD App registration not found. Creating..."
                $appRegistration = New-AzADApplication @InputObject -EA Stop
            } else {
                Write-Information "  Existing AD App registration found '$($appRegistration.Id)'. Skipping create"
            }

            Write-Information "Searching for existing Azure AD App service principal for app registration..."
            $servicePrincipal = Get-AzADServicePrincipal -ApplicationId ($appRegistration.AppId) -EA Stop
            if (-not($servicePrincipal)) {
                Write-Information "  Existing service principal not found. Creating service principal for AD App rgistration ($($appRegistration.AppId))..."
                $servicePrincipal = New-AzADServicePrincipal -ApplicationId ($appRegistration.AppId) -AppRoleAssignmentRequired -EA Stop
            } else {
                Write-Information "  Existing AD App service principal found '$($servicePrincipal.Id)'. Skipping create"
            }

            $appRegistration
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
