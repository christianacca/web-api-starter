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
        $convention = & "./tools/infrastructure/get-product-conventions.ps1" -EnvironmentName dev -AsHashtable
        $infra = & "./tools/infrastructure/get-infrastructure-info.ps1" $convention -AsHashtable
        
        $aks = $convention.Aks.Primary
        $api = $convention.SubProducts.Api
        $funcApp = $convention.SubProducts.InternalApi
        $keyVault = $convention.SubProducts.KeyVault
        $reportsStorage = $convention.SubProducts.PbiReportStorage
        $appResourceGroup = $convention.AppResourceGroup.ResourceName
        
        $sqlServerName = $convention.SubProducts.Sql.Primary.ResourceName
        $sqlServerInstace = "$sqlServerName.database.windows.net"
        $sqlServerDataSource = "tcp:$sqlServerInstace,1433"
        $databaseName = $convention.SubProducts.Db.ResourceName
        
        $apiSecretValues = Get-DotnetUserSecrets -UserSecretsId d4101dd7-fec4-4011-a0e8-65748f7ee73c
        $apiDevAppSettings = Get-Content ./src/Template.Api/appsettings.Development.json | ConvertFrom-Json
        
        # ----------- Deploy Database migrations -----------
        ./tools/dev-scripts/deploy-db.ps1 -SqlServerName $sqlServerName -DatabaseName $databaseName -EA Stop

        # ----------- Deploy API to AKS -----------         
        $dnsZoneName = Invoke-Exe {
            az aks show -g $aks.ResourceGroupName -n $aks.ResourceName --query addonProfiles.httpApplicationRouting.config.HTTPApplicationRoutingZoneName -otsv
        } -EA SilentlyContinue
        $apiHostName = $dnsZoneName ?? $api.HostName
        
        $apiParams = @{
            ConfigureAppSettingsJson = { param([Hashtable] $Settings)
                $Settings.Api.Database.DataSource = $sqlServerDataSource
                $Settings.Api.Database.InitialCatalog = $databaseName
                $Settings.Api.Database.UserID = $infra.Api.ManagedIdentityClientId
                $Settings.Api.DefaultAzureCredentials.ManagedIdentityClientId = $infra.Api.ManagedIdentityClientId
                $Settings.Api.FunctionsAppToken.Audience = $funcApp.AuthTokenAudience
                $Settings.Api.FunctionsAppQueue.ServiceUri = "https://$($funcApp.StorageAccountName).queue.core.windows.net"
                $Settings.Api.KeyVaultName = $keyVault.ResourceName
                $Settings.Api.ReverseProxy.Clusters.FunctionsApp.Destinations.Primary.Address = "https://$($funcApp.HostName)"
                $Settings.Api.TokenProvider.Authority = 'https://mrisaas.oktapreview.com/oauth2/aus1eyja66s1cBkTt0h8'
                $Settings.ApplicationInsights.AutoCollectActionArgs = $true
                $Settings.ApplicationInsights.ConnectionString = $infra.AppInsights.ConnectionString
                if ($apiSecretValues['CentralIdentity_Credentials_Password']) {
                    $Settings.CentralIdentity.Credentials.Password = $apiSecretValues.CentralIdentity_Credentials_Password
                }
                $Settings.CentralIdentity.BaseUri = $apiDevAppSettings.CentralIdentity.BaseUri
            }
            Values                  =   @{
                'api.image.registry' = "$($convention.Aks.RegistryName).azurecr.io"
                'api.image.tag' = $BuildNumber
                'api.podLabels.aadpodidbinding' = $api.ManagedIdentity.BindingSelector
                'api.podLabels.releasedate' = Get-Date -Format 'yyyy-MM-ddTHH.mm.ss'
                'api.ingress.hostname' = $apiHostName
                'api.healthIngress.enabled' = 'false'
            }
            HelmChartName           =   $convention.Aks.HelmChartName
            AksNamespace            =   $convention.Aks.Namespace
        }
        
        if ($dnsZoneName) {
            $apiParams.Values['api.ingress.extraTls'] = 'null'
            $apiParams.Values['api.ingress.annotations.kubernetes\.io/ingress\.class'] = 'addon-http-application-routing'
        }
        ./tools/dev-scripts/deploy-api.ps1 @apiParams -InfA Continue -EA Stop

        
        # ----------- Deploy Function app -----------
        $funcParams = @{
            AppSettings                     =   @{
            # for list of in-built settings see: https://docs.microsoft.com/en-us/azure/azure-functions/functions-app-settings
                APPINSIGHTS_INSTRUMENTATIONKEY = $infra.AppInsights.ConnectionString
            }
            ConfigureAppSettingsJson        =   { param([Hashtable] $Settings)
                $Settings.InternalApi.Database.DataSource = $sqlServerDataSource
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
        ./tools/dev-scripts/deploy-functions @funcParams -EA Stop
        

        Write-Host '******************* Summary: start ******************************'
        Write-Host "Api Url: http://$apiHostName" -ForegroundColor Yellow
        Write-Host "Api Health Url: http://$apiHostName/health" -ForegroundColor Yellow
        Write-Host "Function App Url: https://$($funcApp.HostName)" -ForegroundColor Yellow
        Write-Host "Azure SQL Public Url: https://$($sqlServerInstace):1433" -ForegroundColor Yellow
        Write-Host '******************* Summary: end ********************************'
        
    }
    catch {
        Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
    }
}
