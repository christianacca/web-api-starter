    [CmdletBinding()]
    param(
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',

        [switch] $Login,
        [string] $SubscriptionId
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        $templatePath = Join-Path $PSScriptRoot arm-templates
    }
    process {
        try {

            if ($Login) {
                Write-Information 'Connecting to Azure AD Account...'

                if ($SubscriptionId) {
                    Connect-AzAccount -Subscription $SubscriptionId -EA Stop | Out-Null
                } else {
                    Connect-AzAccount -EA Stop | Out-Null
                }
            } elseif ($SubscriptionId) {
                Select-AzSubscription -SubscriptionId $SubscriptionId -EA Stop | Out-Null
            }

            $convention = & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $EnvironmentName -AsHashtable
            $armParams = @{
                Location                =   'eastus'
                TemplateParameterObject =   @{
                    settings    =   $convention
                }
                TemplateFile            =   Join-Path $templatePath shared-services.bicep
            }
            Write-Information 'Creating desired resource state'
            New-AzDeployment @armParams -EA Stop | Out-Null
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
