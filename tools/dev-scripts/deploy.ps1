<#
    .SYNOPSIS
    Deploys Application stack
      
#>


[CmdletBinding()]
param(
    [switch] $Login,
    [string] $SubscriptionId
)
begin {
    Set-StrictMode -Version 'Latest'
    $callerEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

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
        $api = $convention.SubProducts.Api
        $funcApp = $convention.SubProducts.Func
        $appResourceGroup = $convention.AppResourceGroup.ResourceName
        
        $apiManagedIdentityClientId = Invoke-Exe {
            az identity show -g $appResourceGroup -n $api.ManagedIdentity --query clientId -otsv
        }
        
        $funcManagedIdentityClientId = Invoke-Exe {
            az identity show -g $appResourceGroup -n $funcApp.ManagedIdentity --query clientId -otsv
        }
        $funcAppId = Invoke-Exe {
            az ad app list --display-name $funcApp.ResourceName
        } | ConvertFrom-Json | Select-Object -First 1 | Select-Object -ExpandProperty appId
        $funcAppHostName = Invoke-Exe {
            az functionapp show -g $appResourceGroup -n $funcApp.ResourceName --query hostNames -otsv
        } | Select-Object -First 1
        $funcAppPublicUrl = "https://$funcAppHostName"
        
        $aksResourceGroup = $convention.Aks.Primary.ResourceGroupName
        $aksClusterName = $convention.Aks.Primary.ResourceName
        $dnsZoneName = Invoke-Exe {
            az aks show -g $aksResourceGroup -n $aksClusterName --query addonProfiles.httpApplicationRouting.config.HTTPApplicationRoutingZoneName -otsv
        }
        $apiHostName = "$appResourceGroup-api.$dnsZoneName"
        $sqlServerName = $convention.SubProducts.Sql.Primary.ResourceName
        $sqlServerInstace = "$sqlServerName.database.windows.net"
        $sqlServerDataSource = "tcp:$sqlServerInstace,1433"
        $databaseName = $convention.SubProducts.Db.ResourceName
        
        $appInsightsInstrumentationKey = '<your_instrumentation_key>'

        
        # ----------- Deploy Database migrations -----------
        ./tools/dev-scripts/deploy-db.ps1 -SqlServerName $sqlServerName -DatabaseName $databaseName -EA Stop
        
        # ----------- Deploy API to AKS -----------
        $apiParams = @{
            ConfigureAppSettingsJson    =   { param([Hashtable] $Settings)
                $Settings.Database.DataSource = $sqlServerDataSource
                $Settings.Database.InitialCatalog = $databaseName
                $Settings.Database.UserID = $apiManagedIdentityClientId
                $Settings.Api.FunctionsAppToken.Audience = $funcAppId
                $Settings.Api.FunctionsAppToken.ManagedIdentityClientId = $apiManagedIdentityClientId
                $Settings.Api.ReverseProxy.Clusters.FunctionsApp.Destinations.Primary.Address = $funcAppPublicUrl
                $Settings.Api.TokenProvider.Authority = 'https://mrisaas.oktapreview.com/oauth2/default'
                $Settings.ApplicationInsights.AutoCollectActionArgs = $true
                $Settings.ApplicationInsights.ConnectionString = "InstrumentationKey=$appInsightsInstrumentationKey"
            }
            Values                  =   @{
                'api.image.registry' = "$($convention.Aks.RegistryName).azurecr.io"
                'api.podLabels.aadpodidbinding' = $api.ManagedIdentity
                'api.ingress.hostname' = $apiHostName
            }
            HelmChartName           =   $convention.Aks.HelmChartName
            AksNamespace            =   $convention.Aks.Namespace
        }
        ./tools/dev-scripts/deploy-api.ps1 @apiParams -InformationAction Continue -EA Stop

        
        # ----------- Deploy Function app -----------
        $funcParams = @{
            AppSettings                     =   @{
                # for list of in-built settings see: https://docs.microsoft.com/en-us/azure/azure-functions/functions-app-settings
                APPINSIGHTS_INSTRUMENTATIONKEY   =   $appInsightsInstrumentationKey
            }
            ConfigureAppSettingsJson        =   { param([Hashtable] $Settings)
                $Settings.Database.DataSource = $sqlServerDataSource
                $Settings.Database.InitialCatalog = $databaseName
                $Settings.Database.UserID = $funcManagedIdentityClientId
            }
            ResourceGroup               =   $appResourceGroup
            Name                        =   $funcApp.ResourceName
        }
        ./tools/dev-scripts/deploy-functions @funcParams -EA Stop
        

        Write-Host '******************* Summary: start ******************************'
        Write-Host "Api Url: http://$apiHostName" -ForegroundColor Yellow
        Write-Host "Api Health Url: http://$apiHostName/health" -ForegroundColor Yellow
        Write-Host "Function App Url: $funcAppPublicUrl" -ForegroundColor Yellow
        Write-Host "Azure SQL Public Url: https://$($sqlServerInstace):1433" -ForegroundColor Yellow
        Write-Host '******************* Summary: end ********************************'
        
    }
    catch {
        Write-Error -ErrorRecord $_ -EA $callerEA
    }
}
