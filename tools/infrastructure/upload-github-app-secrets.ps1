    <#
      .SYNOPSIS
      Upload GitHub App credentials to Azure Key Vault
      
      .DESCRIPTION
      Uploads GitHub App private key to Azure Key Vault. Optionally uploads webhook secret 
      if -WebhookSecret parameter is provided. Webhook secret must be provided by the user 
      (empty values are not allowed). Uploads as 'Github--PrivateKeyPem' and 
      optionally 'Github--WebhookSecret'.
      
      .PARAMETER EnvironmentName
      Environment name (dev, qa, rel, demo, staging, prod-*, etc.)
      
      .PARAMETER PemFilePath
      Path to GitHub App private key (.pem file)
      
      .PARAMETER WebhookSecret
      Optional webhook secret. Only uploads webhook secret if this parameter is provided.
      Must be a non-empty value provided by the user.
      If not provided at all, skips webhook secret upload (useful for private key rotation).
      
      .PARAMETER Dry
      Dry run mode - shows what would be uploaded without uploading
      
      .PARAMETER Login
      Perform interactive Azure login before executing
      
      .PARAMETER SubscriptionId
      Azure subscription to use. Defaults to current context.
      
      .PARAMETER SkipInstallModules
      Skip automatic installation of required PowerShell modules (Az). Use this if modules are already installed.
      
      .PARAMETER ModuleInstallAllowClobber
      Allow PowerShell module installation to overwrite existing commands. Use if you encounter module conflicts.
      
      .EXAMPLE
      ./upload-github-app-secrets.ps1 -EnvironmentName dev -PemFilePath "./app.pem"
      Uploads only private key, skips webhook secret
      
      .EXAMPLE
      ./upload-github-app-secrets.ps1 -EnvironmentName prod-na -PemFilePath "./app.pem" -WebhookSecret "my-secret"
      Uploads private key and specified webhook secret
      
      .EXAMPLE
      ./upload-github-app-secrets.ps1 -EnvironmentName dev -PemFilePath "./app.pem" -SkipInstallModules
      Skip module installation check (assumes Az module already installed)
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentName,
    
        [Parameter(Mandatory)]
        [string] $PemFilePath,
    
        [string] $WebhookSecret,
    
        [switch] $Dry,
        [switch] $Login,
        [string] $SubscriptionId,
        [switch] $SkipInstallModules,
        [switch] $ModuleInstallAllowClobber
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    
        . "$PSScriptRoot/ps-functions/Invoke-Exe.ps1"
        . "$PSScriptRoot/ps-functions/Set-AzureAccountContext.ps1"
        . "$PSScriptRoot/ps-functions/Install-ScriptDependency.ps1"
        . "$PSScriptRoot/ps-functions/Get-AzModuleInfo.ps1"
    }
    process {
        try {
            $environments = & "$PSScriptRoot/get-product-environment-names.ps1"
            
            if ($EnvironmentName -notin $environments) {
                throw "EnvironmentName '$EnvironmentName' is not valid. Valid values are: $($environments -join ', ')"
            }

            $modules = @(Get-AzModuleInfo)
            Install-ScriptDependency -ImportOnly:$SkipInstallModules -ModuleInstallAllowClobber:$ModuleInstallAllowClobber -Module $modules
    
            Set-AzureAccountContext -Login:$Login -SubscriptionId $SubscriptionId
            
            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable
            $keyVaultName = $convention.SubProducts.KeyVault.ResourceName
            $apiDomain = $convention.SubProducts.Api.HostName
            $webhookUrl = "https://$apiDomain/api/github/webhooks"
            $githubAppName = $convention.SubProducts.Github.AppName
            $githubAppSlug = $convention.SubProducts.Github.AppSlug
            
            if (-not $keyVaultName) {
                throw "Could not determine Key Vault name for environment '$EnvironmentName'. Check product conventions."
            }
    
            if (-not (Test-Path $PemFilePath)) {
                throw "PEM file not found: $PemFilePath"
            }
    
            $PemFilePath = Resolve-Path $PemFilePath | Select-Object -ExpandProperty Path
            
            $pemContent = Get-Content $PemFilePath -Raw
            if ($pemContent -notmatch "-----BEGIN.*PRIVATE KEY-----") {
                throw "File does not appear to be a valid PEM private key file: $PemFilePath"
            }
    
            $shouldUploadWebhookSecret = $PSBoundParameters.ContainsKey('WebhookSecret')
            
            if ($shouldUploadWebhookSecret) {
                if ([string]::IsNullOrEmpty($WebhookSecret)) {
                    throw "WebhookSecret cannot be empty. Please provide a webhook secret value."
                }
            } else {
                Write-Host "Skipping webhook secret upload (not provided)" -ForegroundColor Yellow
            }
            
            $configSummary = [PsCustomObject]@{
                'Key Vault Name'        = $keyVaultName
                'GitHub App Name'       = $githubAppName
                'GitHub App Slug'       = $githubAppSlug
                'GitHub Webhook URL'    = $webhookUrl
                'Webhook Secret'        = if ($shouldUploadWebhookSecret) { '************ (provided)' } else { '(not uploading)' }
            }
    
            if (-not $Dry) {
                Invoke-Exe {
                    az keyvault secret set `
                        --vault-name $keyVaultName `
                        --name "Github--PrivateKeyPem" `
                        --file $PemFilePath `
                        --output none
                }
                
                if ($shouldUploadWebhookSecret) {
                    Invoke-Exe {
                        az keyvault secret set `
                            --vault-name $keyVaultName `
                            --name "Github--WebhookSecret" `
                            --value $WebhookSecret `
                            --output none
                    }
                }
    
                Write-Host "`nUpload completed successfully" -ForegroundColor Green
                Write-Host "`nConfiguration Details:" -ForegroundColor Cyan
                $configSummary | Format-Table -AutoSize
            }
            else {
                Write-Host "`n[DRY RUN] Configuration Details:" -ForegroundColor Magenta
                $configSummary | Format-Table -AutoSize
                Write-Host "`n[DRY RUN] Would upload to Key Vault: $keyVaultName" -ForegroundColor Magenta
                Write-Host "  - Github--PrivateKeyPem (from: $PemFilePath)" -ForegroundColor Magenta
                if ($shouldUploadWebhookSecret) {
                    Write-Host "  - Github--WebhookSecret" -ForegroundColor Magenta
                }
            }
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
