function Set-GithubFederatedCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $CredentialName,
        
        [Parameter(Mandatory)]
        [string] $AppRegistrationName,

        [Parameter(Mandatory)]
        [string] $GitOrganisationName,

        [Parameter(Mandatory)]
        [string] $GitRepositoryName,

        [Parameter(Mandatory)]
        [string] $EnvironmentName
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
        . "$PSScriptRoot/Invoke-Exe.ps1"
    }
    process {
        try {
            Write-Information "Set Github federated crendential to '$AppRegistrationName'..."

            $adRegistration = Invoke-Exe {
                az ad app list --display-name $AppRegistrationName
            } | ConvertFrom-Json | Select-Object -First 1
            
            if (-not($adRegistration)) {
                throw "Cannot find AD App registration for '$AppRegistrationName'"
            }
            
            $credentialsUrl = "https://graph.microsoft.com/beta/applications/$($adRegistration.objectId)/federatedIdentityCredentials"
            $credentialsListUrl = '{0}?$filter = name eq ''{1}''' -f $credentialsUrl, $CredentialName

            Write-Information "  Searching for existing federated credential '$CredentialName'"
            $existingCredential = Invoke-Exe { az rest --url $credentialsListUrl } -EA SilentlyContinue |
                ConvertFrom-Json |
                Select-Object -ExpandProperty value

            $credential = @{
                name        =   $CredentialName
                issuer      =   'https://token.actions.githubusercontent.com'
                subject     =   'repo:{0}/{1}:environment:{2}' -f $GitOrganisationName, $GitRepositoryName, $EnvironmentName
                description =   "github actions deploy to $EnvironmentName"
                audiences   =   @('api://AzureADTokenExchange')
            }
            if ($existingCredential) {
                $credential.Remove('name')
            }
            
            $payload = $credential | ConvertTo-Json -Compress | ConvertTo-Json
            if ($existingCredential) {
                Write-Information "  Existing federated credential '$CredentialName' found. Updating..."
                $credentialsUrl = "$credentialsUrl/$($existingCredential.id)"
                Invoke-Exe { az rest --method PATCH --uri $credentialsUrl --body $payload } | Out-Null
            } else {
                Write-Information "  Existing federated credential '$CredentialName' not found. Creating..."
                Invoke-Exe { az rest --method POST --uri $credentialsUrl --body $payload } | Out-Null    
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}