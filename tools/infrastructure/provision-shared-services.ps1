    [CmdletBinding()]
    param(
        [string] $EnvironmentName = 'dev',
        
        [switch] $GrantRbacManagement,
        [switch] $CreateSharedContainerRegistry,
        [switch] $CreateSharedKeyVault,
        
        [string] $CertificateMaintainerGroupName = 'sg.role.it.itops.cloud',

        [switch] $Login,
        [string] $SubscriptionId,
        [switch] $ListModuleRequirementsOnly,
        [switch] $SkipInstallModules
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/ps-functions/Get-AzModuleInfo.ps1"
        . "$PSScriptRoot/ps-functions/Get-ScriptDependencyList.ps1"
        . "$PSScriptRoot/ps-functions/Install-ScriptDependency.ps1"
        . "$PSScriptRoot/ps-functions/Set-AzureAccountContext.ps1"
        . "$PSScriptRoot/ps-functions/Set-AADGroup.ps1"

        $templatePath = Join-Path $PSScriptRoot arm-templates
    }
    process {
        try {

            # Tip: you can also print out listing for the conventions. See the examples in ./tools/infrastructure/print-product-convention-table.ps1
            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable
            $defaultProdEnvName = "prod-$($convention.DefaultRegion)"
            
            if ($GrantRbacManagement -and $EnvironmentName -ne $defaultProdEnvName) {
                throw "Granting RBAC management is only required (and supported) in $defaultProdEnvName environment"
            }

            $modules = @(Get-AzModuleInfo)
            if ($ListModuleRequirementsOnly) {
                Get-ScriptDependencyList -Module $modules
                return
            } else {
                Install-ScriptDependency -ImportOnly:$SkipInstallModules -Module $modules
            }

            Set-AzureAccountContext -Login:$Login -SubscriptionId $SubscriptionId

            $currentSubscriptionId = (Get-AzContext).Subscription.Id
            
            if ($CreateSharedContainerRegistry) {
                $deployableRegistries = $convention.ContainerRegistries.Available | Where-Object SubscriptionId -eq $currentSubscriptionId
                if (-not($deployableRegistries)) {
                    Write-Warning "Container registries are not deployable in current subscription: $currentSubscriptionId"
                } else {
                    $acrParams = @{
                        Location                =   $convention.AzureRegion.Default.Primary.Name
                        TemplateFile            =   Join-Path $templatePath 'shared-acr-services.bicep'
                        TemplateParameterObject =   @{
                            containerRegistries =   $convention.ContainerRegistries.Available
                        }
                    }
                    Write-Information 'Creating shared Azure container registries in current azure subscription'
                    New-AzDeployment @acrParams -EA Stop | Out-Null
                }
            }

            if ($CreateSharedKeyVault) {
                Write-Information "Ensuring Entra-ID secruity group exists with name: '$CertificateMaintainerGroupName'"
                $group = Set-AADGroup $CertificateMaintainerGroupName
                $certKeyVaults = @(
                    $convention.TlsCertificates.Dev.KeyVault
                    $convention.TlsCertificates.Prod.KeyVault
                )
                $deployableCertKeyVaults = $certKeyVaults | Where-Object SubscriptionId -eq $currentSubscriptionId
                if (-not($deployableCertKeyVaults)) {
                    Write-Warning "Certificate key vaults are not deployable in current subscription: $currentSubscriptionId"
                } else {
                    $kvParams = @{
                        Location                =   $convention.AzureRegion.Default.Primary.Name
                        TemplateFile            =   Join-Path $templatePath 'shared-keyvault-services.bicep'
                        TemplateParameterObject =   @{
                            certMaintainerGroupId   =   $group.Id
                            tlsCertificateKeyVaults =   $certKeyVaults                    }
                    }
                    Write-Information 'Creating shared Azure key vaults in current azure subscription'
                    New-AzDeployment @kvParams -EA Stop | Out-Null    
                }
            }
            
            if ($GrantRbacManagement) {
                $clientIds = & "$PSScriptRoot/get-product-azure-connections.ps1" -PropertyName clientId
                $otherProdServicePrincipalIds = $clientIds.GetEnumerator() |
                    Where-Object { ($_.Key -like 'prod-*') -and ($_.key -ne $defaultProdEnvName) } |
                    Select-Object -Exp Value -Unique |
                    ForEach-Object { Get-AzADServicePrincipal -ApplicationId $_ -EA stop | Select-Object -Exp Id }
                $rbacParams = @{
                    Location                =   $convention.AzureRegion.Default.Primary.Name
                    TemplateFile            =   Join-Path $templatePath 'cli-permissions.bicep'
                    TemplateParameterObject = @{
                        devServicePrincipalId           =   Get-AzADServicePrincipal -ApplicationId $clientIds['dev'] | Select-Object -Exp Id
                        otherProdServicePrincipalIds    =   @($otherProdServicePrincipalIds)
                        settings                        =   $convention
                    }
                }
                Write-Information 'Granting RBAC management permissions to service principals'
                New-AzDeployment @rbacParams -EA Stop | Out-Null
            }
            
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
