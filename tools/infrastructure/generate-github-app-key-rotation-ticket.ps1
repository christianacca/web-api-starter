    <#
      .SYNOPSIS
      Generate ServiceNow ticket request for GitHub App private key rotation
      
      .DESCRIPTION
      Generates a ServiceNow ticket subject and body with detailed instructions for rotating
      the GitHub App private key for a specific environment. This process involves the GitHub 
      Admin Team generating a new key, the App Admin Team uploading it to the environment 
      Key Vault, and the GitHub Admin Team deleting the old key.
      
      .PARAMETER EnvironmentName
      The environment name (e.g., dev, test, prod). Defaults to 'dev'.
      
      .EXAMPLE
      ./generate-github-app-key-rotation-ticket.ps1 -EnvironmentName prod
      Generates ServiceNow ticket details for GitHub App private key rotation in production
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$EnvironmentName = 'dev'
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable
            $productName = $convention.Product.Name
            $githubOwner = $convention.SubProducts.Github.Owner
            $githubRepo = $convention.SubProducts.Github.Repo
            
            $repository = "$githubOwner/$githubRepo"
            
            $separator = "─" * 61
            
            $subject = "GitHub App Private Key Rotation Request - $productName ($EnvironmentName)"
            
            $body = @"
Request Type: GitHub App Private Key Rotation

GitHub App Information:
- GitHub App Name: $productName
- Environment: $EnvironmentName
- Repository: $repository

Rotation Process:
1. GitHub Admin Team:
   - Navigate to GitHub App settings
   - Generate a new private key (.pem file)
   - Download the new .pem file
   - Securely share the new .pem file with App Admin Team
   - DO NOT delete the old key yet

2. App Admin Team:
   - Receive new .pem file from GitHub Admin Team
   - Upload to $EnvironmentName environment Key Vault using:
     tools/infrastructure/upload-github-app-secrets.ps1 -EnvironmentName $EnvironmentName -PemFilePath <path>
   - Verify successful upload to $EnvironmentName environment
   - Confirm completion to GitHub Admin Team

3. GitHub Admin Team:
   - After receiving confirmation from App Admin Team
   - Delete the OLD private key from GitHub App settings
   - Confirm deletion

Please refer to the GitHub App Creation Guide - Security and Private Key Management section:
https://github.com/christianacca/web-api-starter/blob/master/docs/github-app-creation.md#security-and-private-key-management
"@

            Write-Host "`nServiceNow Ticket Subject:" -ForegroundColor Cyan
            Write-Host $separator -ForegroundColor Gray
            Write-Host $subject -ForegroundColor White
            Write-Host ""
            Write-Host "ServiceNow Ticket Body:" -ForegroundColor Cyan
            Write-Host $separator -ForegroundColor Gray
            Write-Host $body -ForegroundColor White
            Write-Host ""
            Write-Host "✓ Copy the above information and create a ServiceNow ticket" -ForegroundColor Green
            Write-Host ""
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
