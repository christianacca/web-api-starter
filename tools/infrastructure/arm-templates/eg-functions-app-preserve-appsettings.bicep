@description('List of origins that should be allowed to make cross-origin\ncalls')
param corsAllowedOrigins array = []

@description('Specify whether CORS requests with credentials are allowed. See\nhttps://developer.mozilla.org/en-US/docs/Web/HTTP/CORS#Requests_with_credentials\nfor more details')
param corsSupportCredentials bool = false

@description('Specify the name of the function application')
param functionAppName string

@description('Specify the location for the function application resources')
param location string = resourceGroup().location

@description('A list of Resource ID of the user-assigned managed identities, in the form of /subscriptions/<subscriptionId>/resourceGroups/<ResourceGroupName>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<managedIdentity>.')
param managedIdentityResourceIds array

@description('The name of the Storage Account')
param storageAccountName string = toLower('funcsa${uniqueString(resourceGroup().id)}')

var hostingPlanName = functionAppName

var managedIdentityResourceIdMaps = map(managedIdentityResourceIds, (resourceId) => {resourceId: resourceId})
var userAssignedIdentities = reduce(managedIdentityResourceIdMaps, {}, (cur, next) => union(cur, {
  '${next.resourceId}': {}
}))

resource functionApp 'Microsoft.Web/sites@2019-08-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: userAssignedIdentities
  }
  properties: {
    siteConfig: {
      netFrameworkVersion: 'v7.0'  
      cors: {
        allowedOrigins: corsAllowedOrigins
        supportCredentials: corsSupportCredentials
      }
      http20Enabled: true
    }
    httpsOnly: true
    clientAffinityEnabled: false
    serverFarmId: hostingPlan.id
  }
  dependsOn: [
    storageAccount
  ]
}

// Create-Update the webapp app settings.
module appSettings 'appsettings.bicep' = {
  name: '${functionAppName}-appsettings'
  params: {
    webAppName: functionApp.name
    // Get the current appsettings
    currentAppSettings: list(resourceId('Microsoft.Web/sites/config', functionApp.name, 'appsettings'), '2020-12-01').properties
    appSettings: {
      FUNCTIONS_EXTENSION_VERSION: '~4'
      FUNCTIONS_WORKER_RUNTIME: 'dotnet-isolated'
      AzureWebJobsFeatureFlags: 'EnableHttpProxying'
      AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
      AzureWebJobsDashboard: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
      WEBSITE_CONTENTSHARE: toLower(functionAppName)
      WEBSITE_RUN_FROM_PACKAGE: '1'
    }
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2019-08-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: storageAccountName
  location: location
  kind: 'Storage'
  sku: {
    name: 'Standard_LRS'
  }
}

resource storageAccountName_default_default_queue 'Microsoft.Storage/storageAccounts/queueServices/queues@2019-06-01' = {
  name: '${storageAccountName}/default/default-queue'
  dependsOn: [
    storageAccount
  ]
}
