<#
    .SYNOPSIS
    Deploys API to AKS using helm

    .EXAMPLE
    az aks show --resource-group dev-aks-eastus --name dev-aks-eastus --query addonProfiles.httpApplicationRouting.config.HTTPApplicationRoutingZoneName -otsv
    $values = @{ 
        'api.image.registry' = '<YourAzureRegistry>.azurecr.io'
        'api.podLabels.aadpodidbinding' = 'web-api-starter-api-identity'
        'api.ingress.hostname' = 'web-api-starter-api.<DNS_ENTRY_NOTED_ABOVE>'
    }
    ./tools/dev-scripts/deploy-api.ps1 -HelmChartName my-app -AksNamespace app-my-app -Values $values -ConfigureAppSettingsJson { param([Hashtable] $Settings) 
        $Settings.Database.DataSource = 'tcp:web-api-starter-sql.database.windows.net,1433'
        $Settings.Database.InitialCatalog = 'web-api-starter-sql-db'
        $Settings.Database.UserID = '<ApiManagedIdentityClientId>'
        $Settings.Api.FunctionsAppToken.Audience = '<FunctionAppApplicationId>'
        $Settings.Api.FunctionsAppToken.ManagedIdentityClientId = '<ApiManagedIdentityClientId>'
        $Settings.Api.ReverseProxy.Clusters.FunctionsApp.Destinations.Primary.Address = 'https://web-api-stater-func.azurewebsites.net'
        $Settings.Api.TokenProvider.Authority = 'https://mrisaas.oktapreview.com/oauth2/default'
        $Settings.ApplicationInsights.AutoCollectActionArgs = $true
        $Settings.ApplicationInsights.ConnectionString = "InstrumentationKey=<YourAppInsightsKey>"
    }
    
    Description
      -----------
    Deploys API to AKS using the ket/value pairs from $values to override the values.yaml file
      
#>
    
    [CmdletBinding()]
    param(
        [string] $Path = 'out',
    
        [Parameter(Mandatory)]
        [string] $HelmChartName,
    
        [Parameter(Mandatory)]
        [string] $AksNamespace,
    
        [switch] $ShowOnly = $false,
        [switch] $DryRun = $false,
        [Hashtable] $Values = @{},
        [ScriptBlock] $ConfigureAppSettingsJson
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "./tools/infrastructure/ps-functions/Invoke-ExeExpression.ps1"
        . "./tools/dev-scripts/Set-AppSettings.ps1"
        
        $helmFolderPath = Join-Path $Path helm-chart
    }
    process {
        try {
            $appSettingsFolderPath = Join-Path $Path helm-chart/Template.Api
            if ($ConfigureAppSettingsJson) {
                Set-AppSettings $appSettingsFolderPath $ConfigureAppSettingsJson
            }
            
            $defaultName = 'web-api-starter'
            if ($HelmChartName -ne $defaultName) {
                $valuesFilePath = "$helmFolderPath/values.yaml"
                $valuesContent = Get-Content $valuesFilePath -Raw
                $valuesContent = $valuesContent.Replace("$defaultName-api-appsettings-json", "$HelmChartName-api-appsettings-json")
                Set-Content $valuesFilePath -Value $valuesContent
            }
            
            Invoke-ExeExpression 'helm repo add bitnami https://charts.bitnami.com/bitnami'
            Invoke-ExeExpression "helm dependency build '$helmFolderPath'"
            
            $appSettingsCheckSum = (Get-FileHash (Join-Path $appSettingsFolderPath appsettings.json)).Hash
            $Values['api.podAnnotations.checksum-appsettings-json'] = $appSettingsCheckSum
            
            $valuesString = $Values.Keys | 
                ForEach-Object { ('{0}={1}' -f  $_, $Values[$_].Replace(',', '\,').Replace('=', '\=')) } | 
                Join-String -Separator ','
            $setParamString = if ($valuesString) { '--set ' + $valuesString } else { '' }
            
            $helmDeploy = if (-not($ShowOnly)) {
                $dryRunParam = if ($DryRun) { '--dry-run' } else { '' }
                "helm upgrade --install --atomic --cleanup-on-fail --create-namespace $HelmChartName '$helmFolderPath' -n $AksNamespace $dryRunParam $setParamString"
            } else {
                "helm template $HelmChartName '$helmFolderPath' $setParamString"
            }
            Invoke-ExeExpression $helmDeploy
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
