    [CmdletBinding()]
    param(
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
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
            
            if ($GrantRbacManagement -and $EnvironmentName -ne 'prod-na') {
                throw 'Granting RBAC management is only required (and supported) in prod-na environment'
            }

            $modules = @(Get-AzModuleInfo)
            if ($ListModuleRequirementsOnly) {
                Get-ScriptDependencyList -Module $modules
                return
            } else {
                Install-ScriptDependency -ImportOnly:$SkipInstallModules -Module $modules
            }

            Set-AzureAccountContext -Login:$Login -SubscriptionId $SubscriptionId

            # Tip: you can also print out listing for the conventions. See the examples in ./tools/infrastructure/print-product-convention-table.ps1
            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable
            
            if ($CreateSharedContainerRegistry) {
                $acrParams = @{
                    Location                =   'eastus'
                    TemplateFile            =   Join-Path $templatePath 'shared-acr-services.bicep'
                    TemplateParameterObject =   @{
                        containerRegistries =   $convention.ContainerRegistries.Available
                    }
                }
                Write-Information 'Creating shared Azure container registries in current azure subscription'
                New-AzDeployment @acrParams -EA Stop | Out-Null
            }

            if ($CreateSharedKeyVault) {
                Write-Information "Ensuring Entra-ID secruity group exists with name: '$CertificateMaintainerGroupName'"
                $group = Set-AADGroup $CertificateMaintainerGroupName
                $kvParams = @{
                    Location                =   'eastus'
                    TemplateFile            =   Join-Path $templatePath 'shared-keyvault-services.bicep'
                    TemplateParameterObject =   @{
                        certMaintainerGroupId   =   $group.Id
                        tlsCertificateKeyVaults =   @(
                            $convention.TlsCertificates.Dev.KeyVault
                            $convention.TlsCertificates.Prod.KeyVault
                        )
                    }
                }
                Write-Information 'Creating shared Azure key vaults in current azure subscription'
                New-AzDeployment @kvParams -EA Stop | Out-Null
            }
            
            if ($GrantRbacManagement) {
                $clientIds = & "$PSScriptRoot/get-product-azure-connections.ps1" -PropertyName clientId
                $rbacParams = @{
                    Location                =   'eastus'
                    TemplateFile            =   Join-Path $templatePath 'cli-permissions.bicep'
                    TemplateParameterObject = @{
                        devServicePrincipalId       =   Get-AzADServicePrincipal -ApplicationId $clientIds['dev'].Id | Select-Object -Exp Id
                        apacProdServicePrincipalId  =   Get-AzADServicePrincipal -ApplicationId $clientIds['prod-apac'].Id | Select-Object -Exp Id
                        emeaProdServicePrincipalId  =   Get-AzADServicePrincipal -ApplicationId $clientIds['prod-emea'].Id | Select-Object -Exp Id
                        settings                    =   $convention
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
