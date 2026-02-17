    <#
      .SYNOPSIS
      Upload GitHub App credentials to Azure Key Vault
      
      .DESCRIPTION
      Uploads GitHub App private key and/or webhook secret to Azure Key Vault. 
      At least one of -PemFilePath or -WebhookSecret must be provided.
      Uploads as 'Github--PrivateKeyPem' and/or 'Github--WebhookSecret'.
      
      .PARAMETER EnvironmentName
      Environment name (dev, qa, rel, demo, staging, prod-*, etc.)
      
      .PARAMETER PemFilePath
      Optional path to GitHub App private key (.pem file). If provided, uploads the private key.
      
      .PARAMETER WebhookSecret
      Optional webhook secret. If provided, uploads the webhook secret.
      Must be a non-empty value.
      
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
      ./upload-github-app-secrets.ps1 -EnvironmentName prod-na -WebhookSecret "my-secret"
      Uploads only webhook secret, skips private key
      
      .EXAMPLE
      ./upload-github-app-secrets.ps1 -EnvironmentName prod-na -PemFilePath "./app.pem" -WebhookSecret "my-secret"
      Uploads both private key and webhook secret
      
      .EXAMPLE
      ./upload-github-app-secrets.ps1 -EnvironmentName dev -PemFilePath "./app.pem" -SkipInstallModules
      Skip module installation check (assumes Az module already installed)
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentName,
    
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

            if (-not $PSBoundParameters.ContainsKey('PemFilePath') -and -not $PSBoundParameters.ContainsKey('WebhookSecret')) {
                throw "At least one of -PemFilePath or -WebhookSecret must be provided."
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
    
            $shouldUploadPemFile = $PSBoundParameters.ContainsKey('PemFilePath')
            $shouldUploadWebhookSecret = $PSBoundParameters.ContainsKey('WebhookSecret')
    
            if ($shouldUploadPemFile) {
                if (-not (Test-Path $PemFilePath)) {
                    throw "PEM file not found: $PemFilePath"
                }
        
                $PemFilePath = Resolve-Path $PemFilePath | Select-Object -ExpandProperty Path
                
                $pemContent = Get-Content $PemFilePath -Raw
                if ($pemContent -notmatch "-----BEGIN.*PRIVATE KEY-----") {
                    throw "File does not appear to be a valid PEM private key file: $PemFilePath"
                }
            } else {
                Write-Host "Skipping private key upload (not provided)" -ForegroundColor Yellow
            }
            
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
                'Private Key'           = if ($shouldUploadPemFile) { '(uploading)' } else { '(not uploading)' }
                'Webhook Secret'        = if ($shouldUploadWebhookSecret) { '************ (provided)' } else { '(not uploading)' }
            }
    
            if (-not $Dry) {
                if ($shouldUploadPemFile) {
                    Invoke-Exe {
                        az keyvault secret set `
                            --vault-name $keyVaultName `
                            --name "Github--PrivateKeyPem" `
                            --file $PemFilePath `
                            --output none
                    }
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
                if ($shouldUploadPemFile) {
                    Write-Host "  - Github--PrivateKeyPem (from: $PemFilePath)" -ForegroundColor Magenta
                }
                if ($shouldUploadWebhookSecret) {
                    Write-Host "  - Github--WebhookSecret" -ForegroundColor Magenta
                }
            }
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
