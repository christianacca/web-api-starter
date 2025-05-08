    [CmdletBinding()]
    param(
        [ValidateSet('dev/test', 'prod')]
        [string] $EnvironmentType,  
        
        [string] $CertificateMaintainerGroupName = 'sg.role.it.itops.cloud',
        [switch] $Login,
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
            $modules = @(Get-AzModuleInfo)
            if ($ListModuleRequirementsOnly) {
                Get-ScriptDependencyList -Module $modules
                return
            }
            
            if ($null -eq $EnvironmentType) {
                throw "EnvironmentType is required"
            }
            
            Install-ScriptDependency -ImportOnly:$SkipInstallModules -Module $modules

            # Tip: you can also print out listing for the conventions. See the examples in ./tools/infrastructure/print-product-convention-table.ps1
            $initialConvention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName dev -AsHashtable

            $environmentName = $EnvironmentType -eq 'prod' ? $initialConvention.DefaultProdEnvName : 'dev'
            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $environmentName -AsHashtable

            Set-AzureAccountContext -Login:$Login -SubscriptionId $convention.Subscriptions[$environmentName]

            Write-Information "Ensuring Entra-ID secruity group exists with name: '$CertificateMaintainerGroupName'"
            $group = Set-AADGroup $CertificateMaintainerGroupName
            
            $sharedServicesParams = @{
                Location                =   $convention.AzureRegion.Default.Primary.Name
                TemplateFile            =   Join-Path $templatePath 'main-shared-services.bicep'
                TemplateParameterObject =   @{
                    certMaintainerGroupId   =   $group.Id
                    # Granting RBAC management is only required (and supported) when deploying to the default prod environment
                    grantRbacManagement     =   $EnvironmentType -eq 'prod'
                    settings                =   $convention
                }
            }
            Write-Information 'Creating shared services and assigning RBAC management permissions in current azure subscription'
            New-AzDeployment @sharedServicesParams -EA Stop | Out-Null            
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
