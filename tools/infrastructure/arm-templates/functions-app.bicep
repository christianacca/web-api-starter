@description('List of origins that should be allowed to make cross-origin\ncalls')
param corsAllowedOrigins array = []

@description('Specify whether CORS requests with credentials are allowed. See\nhttps://developer.mozilla.org/en-US/docs/Web/HTTP/CORS#Requests_with_credentials\nfor more details')
param corsSupportCredentials bool = false

@description('Specify the name of the function application')
param functionAppName string

@description('Specify the location for the function application resources')
param location string = resourceGroup().location

@description('The Application (Client) ID of the AD App Registration that the function is a part of.')
param appClientId string

@description('A list of Resource ID of the user-assigned managed identities, in the form of /subscriptions/<subscriptionId>/resourceGroups/<ResourceGroupName>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<managedIdentity>.')
param managedIdentityResourceIds array

@description('The name of the Storage Account')
param storageAccountName string = toLower('funcsa${uniqueString(resourceGroup().id)}')

@description('The ID of the tenant providing auth token')
param tenantID string = subscription().tenantId

@description('The connection string for the application insights instance used to monitor function app')
param appInsightsConnectionString string = ''

@description('The name of the function app as it appears in application insights')
param appInsightsCloudRoleName string = functionAppName

@description('Create a default message queue for this function app')
param deployDefaultStorageQueue bool = false

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
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'AzureWebJobsFeatureFlags'
          value: 'EnableHttpProxying'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'WEBSITE_CLOUD_ROLENAME'
          value: appInsightsCloudRoleName
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
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
}

resource functionAppName_authsettingsV2 'Microsoft.Web/sites/config@2020-12-01' = {
  parent: functionApp
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'Return401'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: 'https://sts.windows.net/${tenantID}/'
          clientId: appClientId
          clientSecretSettingName: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
        }
        validation: {
          allowedAudiences: [
            'api://${functionAppName}'
          ]
        }
      }
    }
    login: {
      tokenStore: {
        enabled: true
      }
    }
    httpSettings: {
      requireHttps: true
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

resource storageAccountName_default_default_queue 'Microsoft.Storage/storageAccounts/queueServices/queues@2019-06-01' = if (deployDefaultStorageQueue) {
  name: '${storageAccountName}/default/default-queue'
  dependsOn: [
    storageAccount
  ]
}

resource storageAccountName_default_default_queue_poison 'Microsoft.Storage/storageAccounts/queueServices/queues@2019-06-01' = if (deployDefaultStorageQueue) {
  name: '${storageAccountName}/default/default-queue-poison'
  dependsOn: [
    storageAccount
  ]
}
