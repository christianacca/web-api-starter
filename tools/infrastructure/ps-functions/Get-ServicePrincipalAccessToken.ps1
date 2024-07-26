function Get-ServicePrincipalAccessToken {
    <#
      .SYNOPSIS
      Get an access token to access an Azure resource on behalf of the service principal supplied
      
      .PARAMETER Credential
      The credentials of a service principal to sign in to Azure to set the security context for token acquistion
      
      .PARAMETER ResourceUrl
      Resource url for that you're requesting token, e.g. 'https://graph.microsoft.com/'.

      .EXAMPLE
      $creds = Get-Credential -UserName 96a99e94-acdc-41a0-ae6a-0836b968de57
      Get-ServicePrincipalAccessToken $creds -ResourceUrl https://database.windows.net
    
      Description
      -----------
      Get an access token to access the Azure SQL database using the service principal supplied
      
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCredential] $Credential,
        
        [Parameter(Mandatory)]
        [string] $ResourceUrl
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            $servicePrincipalAppId = $Credential.UserName
            Write-Information "Connecting to Azure AD Account using service principal (AppId: '$servicePrincipalAppId')..."
            Connect-AzAccount -ServicePrincipal $true -Credential $Credential -EA Stop | Out-Null

            $azContextInfo = Get-AzContext -EA Stop | Select-Object -ExpandProperty Account | Select-Object Id, Type
            Write-Information "Acquiring access token for $ResourceUrl using context ($azContextInfo)..."
            Get-AzAccessToken -ResourceUrl $ResourceUrl -AsSecureString -EA Stop
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
        finally {
            Disconnect-AzAccount -EA Continue | Out-Null # restore the original loggin context
        }
    }
}