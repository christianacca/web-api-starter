<#
    .SYNOPSIS
    Deploys Application stack
      
#>


[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $BuildNumber,
    [switch] $Login,
    [string] $SubscriptionId
)
begin {
    Set-StrictMode -Version 'Latest'
    $callerEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    . "./tools/dev-scripts/Get-DotnetUserSecrets.ps1"
    . "./tools/infrastructure/ps-functions/Invoke-Exe.ps1"
}
process {
    try {

        if ($Login.IsPresent) {
            Write-Information 'Connecting to Azure AD Account...'
            Invoke-Exe { az login } | Out-Null
        }
        if ($SubscriptionId) {
            Invoke-Exe { az account set --subscription $SubscriptionId } | Out-Null
        }
        
        # **** CRITIAL ****
        # This script only deploys to the primary region NOT the secondary region. This script is intended for dev/local deploys only
        

        # ----------- Gather info about deployment -----------
        $environment = 'dev'
        $convention = & "./tools/infrastructure/get-product-conventions.ps1" -EnvironmentName $environment -AsHashtable
        $infra = & "./tools/infrastructure/get-infrastructure-info.ps1" $convention -AsHashtable
        
        $api = $convention.SubProducts.Api
        $funcApp = $convention.SubProducts.InternalApi
        $keyVault = $convention.SubProducts.KeyVault
        $reportsStorage = $convention.SubProducts.PbiReportStorage
        $appResourceGroup = $convention.AppResourceGroup.ResourceName
        
        $sqlServerName = $convention.SubProducts.Sql.Primary.ResourceName
        $sqlServerInstace = "$sqlServerName.database.windows.net"
        $databaseName = $convention.SubProducts.Db.ResourceName
        
        $apiSecretValues = Get-DotnetUserSecrets -UserSecretsId d4101dd7-fec4-4011-a0e8-65748f7ee73c
        $apiDevAppSettings = Get-Content ./src/Template.Api/appsettings.Development.json | ConvertFrom-Json
        
        # ----------- Deploy Database migrations -----------
        ./tools/dev-scripts/deploy-db.ps1 -SqlServerName $sqlServerName -DatabaseName $databaseName -EA Stop

        # ----------- Deploy API to Azure container apps -----------
        $apiParams = @{
            Name                =   $api.Primary.ResourceName
            ResourceGroup       =   $appResourceGroup
            Image               =   '{0}.azurecr.io/{1}:{2}' -f $convention.ContainerRegistries.Dev.ResourceName, $api.ImageName, $BuildNumber
            EnvVarsObject       =   @{
                'Api__TokenProvider__Authority' = $apiDevAppSettings.Api.TokenProvider.Authority
                'ApplicationInsights__AutoCollectActionArgs' = $true
                'CentralIdentity__Credentials__Password' = $apiSecretValues['CentralIdentity_Credentials_Password'] ? $apiSecretValues.CentralIdentity_Credentials_Password : '??'
                'CentralIdentity__BaseUri' = $apiDevAppSettings.CentralIdentity.BaseUri
                'EnvironmentInfo__EnvId' = $environment
            }
            HealthRequestPath   =   $api.DefaultHealthPath
            TestRevision        =   $true
        }
        $apiAca = ./tools/dev-scripts/create-aca-revision.ps1 @apiParams -InfA Continue -EA Stop

        
        # ----------- Deploy Function app -----------
        $funcParams = @{
            AppSettings                     =   @{
            # for list of in-built settings see: https://docs.microsoft.com/en-us/azure/azure-functions/functions-app-settings
                APPINSIGHTS_INSTRUMENTATIONKEY = $infra.AppInsights.ConnectionString
            }
            ConfigureAppSettingsJson        =   { param([Hashtable] $Settings)
                $Settings.InternalApi.Database.DataSource = $convention.SubProducts.Sql.Primary.DataSource
                $Settings.InternalApi.Database.InitialCatalog = $databaseName
                $Settings.InternalApi.Database.UserID = $infra.InternalApi.ManagedIdentityClientId
                $Settings.InternalApi.DefaultAzureCredentials.ManagedIdentityClientId = $infra.InternalApi.ManagedIdentityClientId
                $Settings.InternalApi.KeyVaultName = $keyVault.ResourceName
                $Settings.InternalApi.ReportBlobStorage.ServiceUri = "https://$($reportsStorage.StorageAccountName).blob.core.windows.net"
            }
            ResourceGroup                   =   $appResourceGroup
            Name                            =   $funcApp.ResourceName
            Path                            =   'out/Template.Functions'
        }
        ./tools/dev-scripts/deploy-functions.ps1 @funcParams -EA Stop
        

        Write-Host '******************* Summary: start ******************************'
        Write-Host "Api Url: https://$($apiAca.configuration.ingress.fqdn)" -ForegroundColor Yellow
        Write-Host "Api Health Url: https://$($apiAca.configuration.ingress.fqdn)/health" -ForegroundColor Yellow
        Write-Host "Function App Url: https://$($funcApp.HostName)" -ForegroundColor Yellow
        Write-Host "Azure SQL Public Url: https://$($sqlServerInstace):1433" -ForegroundColor Yellow
        Write-Host '******************* Summary: end ********************************'
        
    }
    catch {
        Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
    }
}
