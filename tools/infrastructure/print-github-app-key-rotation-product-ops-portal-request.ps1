<#
  .SYNOPSIS
  Generate Product Ops Portal request for GitHub App private key rotation

  .DESCRIPTION
  Generates the Product Ops Portal request title and body with detailed instructions for rotating
  the GitHub App private key for a specific environment. This process involves the GitHub
  Admin Team generating a new key, the App Admin Team uploading it to the environment
  Key Vault, and the GitHub Admin Team deleting the old key.

  .PARAMETER EnvironmentName
  The environment name (e.g., dev, test, prod). Defaults to 'dev'.

  .EXAMPLE
  ./print-github-app-key-rotation-product-ops-portal-request.ps1 -EnvironmentName prod
  Generates Product Ops Portal request details for GitHub App private key rotation in production
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
        $validEnvironments = & "$PSScriptRoot/get-product-environment-names.ps1"

        if ($EnvironmentName -notin $validEnvironments) {
            throw "EnvironmentName '$EnvironmentName' is not valid. Valid values are: $($validEnvironments -join ', ')"
        }

        $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable
        $githubAppName = $convention.SubProducts.Github.AppName
        $githubOwner = $convention.SubProducts.Github.Owner
        $githubRepo = $convention.SubProducts.Github.Repo

        $repository = "$githubOwner/$githubRepo"

        $separator = "─" * 61

        $requestTitle = "GitHub App Private Key Rotation Request - $githubAppName"

        $description = @"
Purpose:
This request is to rotate the GitHub App private key for the $EnvironmentName environment as part of regular security maintenance and compliance with industry best practices.

GitHub App Information:
- GitHub App Name: $githubAppName
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

Please refer to the GitHub App Creation Guide - Private Key Rotation section:
https://github.com/christianacca/web-api-starter/blob/master/docs/github-app-creation.md#part-2-github-admin-team---generate-new-private-key
"@

        Write-Host "`nProduct Ops Portal Request Details:" -ForegroundColor Cyan
        Write-Host $separator -ForegroundColor Gray
        Write-Host ""
        Write-Host "Request Title:" -ForegroundColor Yellow
        Write-Host $requestTitle -ForegroundColor White
        Write-Host ""
        Write-Host "Description:" -ForegroundColor Yellow
        Write-Host $description -ForegroundColor White
        Write-Host ""
    }
    catch {
        Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
    }
}