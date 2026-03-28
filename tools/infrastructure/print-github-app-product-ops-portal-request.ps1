<#
  .SYNOPSIS
  Generate Product Ops Portal request details for GitHub App creation

  .DESCRIPTION
Generates the request details needed in the Product Ops Portal for the
GitHub Admin Team to create a GitHub App for the specified environment. The output
requests an Actions-permissions app for workflow dispatch.

  .PARAMETER EnvironmentName
  Environment name (dev, qa, rel, demo, staging, prod-*, etc.)

  .EXAMPLE
  ./print-github-app-product-ops-portal-request.ps1 -EnvironmentName dev
  Generates Product Ops Portal request details for dev environment
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $EnvironmentName
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
        $apiDomain = $convention.SubProducts.Api.HostName
        $githubAppName = $convention.SubProducts.Github.AppName
        $githubOwner = $convention.SubProducts.Github.Owner
        $githubRepo = $convention.SubProducts.Github.Repo
        $repository = "$githubOwner/$githubRepo"
        $branch = 'master'

        $separator = "─" * 61

        $requestTitle = "GitHub App Creation Request - $githubAppName"

        $description = @"
Purpose:
This GitHub App is required to enable workflow orchestration for the $EnvironmentName environment for 
the Web API starter Project
The application uses GitHub Apps to securely authenticate with GitHub and dispatch GitHub Actions
workflows for this environment.

Environment Details:
- Environment Name: $EnvironmentName
- GitHub App Name: $githubAppName
- API Domain: $apiDomain

Repository Information:
- Repository: $repository
- Branch: $branch

Required Permissions:
- Actions: Read & Write
- Metadata: Read

Next Steps:
1. Create GitHub App with the above configuration
2. Install app to repository: $repository
3. Generate private key (.pem file)
4. Provide the following to App Admin Team:
   - App ID
   - Installation ID
   - Private key .pem file (securely)

Please refer to the GitHub App Creation Guide - GitHub Admin Team Responsibilities:
https://github.com/christianacca/web-api-starter/blob/master/docs/github-app-creation.md#part-2-github-admin-team-responsibilities
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