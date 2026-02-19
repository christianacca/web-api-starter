    <#
      .SYNOPSIS
      Generate ServiceNow ticket request for GitHub App creation
      
      .DESCRIPTION
      Generates a ServiceNow ticket subject and body with all required information for the 
      GitHub Admin Team to create a GitHub App for the specified environment. The output 
      includes environment-specific details such as webhook URL, app name, repository, and 
      required permissions.
      
      .PARAMETER EnvironmentName
      Environment name (dev, qa, rel, demo, staging, prod-*, etc.)
      
      .EXAMPLE
      ./generate-github-app-servicenow-ticket.ps1 -EnvironmentName dev
      Generates ServiceNow ticket details for dev environment
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
            $webhookUrl = $convention.SubProducts.Github.WebhookUrl
            $githubAppName = $convention.SubProducts.Github.AppName
            $githubOwner = $convention.SubProducts.Github.Owner
            $githubRepo = $convention.SubProducts.Github.Repo
            
            $repository = "$githubOwner/$githubRepo"
            $branch = "master"
            
            $separator = "─" * 61
            
            $requestTitle = "GitHub App Creation Request - $githubAppName"
            $requestType = "General IT Request"
            $priority = "3 - Moderate"
            
            $description = @"
Purpose:
This GitHub App is required to enable workflow orchestration for the $EnvironmentName environment for 
the Web API starter Project
The application uses GitHub Apps to securely authenticate with GitHub and receive webhook notifications 
when workflows complete. This allows the application to monitor and respond to GitHub Actions workflow 
execution, enabling us to automate various tasks by using github workflows.

Environment Details:
- Environment Name: $EnvironmentName
- GitHub App Name: $githubAppName
- API Domain: $apiDomain
- Webhook URL: $webhookUrl

Repository Information:
- Repository: $repository
- Branch: $branch

Required Permissions:
- Actions: Read & Write
- Metadata: Read

Webhook Configuration:
- Subscribe to Events: Workflow run
- Webhook Active: Yes

Next Steps:
1. Create GitHub App with the above configuration
2. Install app to repository: $repository
3. Generate private key (.pem file)
4. Generate webhook secret
5. Provide the following to App Admin Team:
   - App ID
   - Installation ID
   - Private key .pem file (securely)
   - Webhook secret (securely)

Please refer to the GitHub App Creation Guide - GitHub Admin Team Responsibilities:
https://github.com/christianacca/web-api-starter/blob/master/docs/github-app-creation.md#part-2-github-admin-team-responsibilities
"@

            Write-Host "`nServiceNow Ticket Details:" -ForegroundColor Cyan
            Write-Host $separator -ForegroundColor Gray
            Write-Host ""
            Write-Host "Request Title:" -ForegroundColor Yellow
            Write-Host $requestTitle -ForegroundColor White
            Write-Host ""
            Write-Host "Request Type:" -ForegroundColor Yellow
            Write-Host $requestType -ForegroundColor White
            Write-Host ""
            Write-Host "Priority:" -ForegroundColor Yellow
            Write-Host $priority -ForegroundColor White
            Write-Host ""
            Write-Host "Description:" -ForegroundColor Yellow
            Write-Host $description -ForegroundColor White
            Write-Host ""
            Write-Host "✓ Copy the above information and create a ServiceNow ticket" -ForegroundColor Green
            Write-Host ""
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
