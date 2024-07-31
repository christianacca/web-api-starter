    [CmdletBinding()]
    param(
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',
        
        [switch] $GrantAcrRbacManagementOnly,

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
            
            if ($GrantAcrRbacManagementOnly -and $EnvironmentName -ne 'prod-na') {
                throw 'Granting ACR RBAC management is only required (and supported) in prod-na environment'
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
            $templateFile = $GrantAcrRbacManagementOnly ? 'cli-acr-permissions.bicep' : 'shared-services.bicep'
            $armParams = @{
                Location                =   'eastus'
                TemplateParameterObject =   @{
                    settings    =   $convention
                }
                TemplateFile            =   Join-Path $templatePath $templateFile
            }
            Write-Information 'Creating desired resource state'
            New-AzDeployment @armParams -EA Stop | Out-Null
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
