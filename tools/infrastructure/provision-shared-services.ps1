    [CmdletBinding()]
    param(
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',
        
        [switch] $GrantRbacManagement,
        [switch] $CreateSharedContainerRegistry,
        [switch] $CreateSharedKeyVault,

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

            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable

            $armParams = @{
                Location                =   'eastus'
                TemplateParameterObject =   @{
                    settings    =   $convention
                }
            }
            
            if ($CreateSharedContainerRegistry) {
                $acrParams = $armParams + @{
                    TemplateFile    =   Join-Path $templatePath 'shared-acr-services.bicep'
                }
                Write-Information 'Creating shared Azure container registries in current azure subscription'
                New-AzDeployment @acrParams -EA Stop | Out-Null
            }

            if ($CreateSharedKeyVault) {
                $kvParams = $armParams + @{
                    TemplateFile    =   Join-Path $templatePath 'shared-keyvault-services.bicep'
                }
                Write-Information 'Creating shared Azure key vaults in current azure subscription'
                New-AzDeployment @kvParams -EA Stop | Out-Null
            }
            
            if ($GrantRbacManagement) {
                $rbacParams = $armParams + @{
                    TemplateFile    =   Join-Path $templatePath 'cli-permissions.bicep'
                }
                Write-Information 'Granting RBAC management permissions to service principals'
                New-AzDeployment @rbacParams -EA Stop | Out-Null
            }
            
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
