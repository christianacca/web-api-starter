extension 'br:mcr.microsoft.com/bicep/extensions/microsoftgraph/v1.0:0.1.8-preview'

@description('List of principal ids that are allowed to make http requests to the function app')
param allowedPrincipalIds string[] = []

@description('List of origins that should be allowed to make cross-origin\ncalls')
param corsAllowedOrigins array = []

@description('Specify whether CORS requests with credentials are allowed. See\nhttps://developer.mozilla.org/en-US/docs/Web/HTTP/CORS#Requests_with_credentials\nfor more details')
param corsSupportCredentials bool = false

@description('Specify the name of the function application')
param functionAppName string

@description('Specify the location for the function application resources')
param location string = resourceGroup().location

@description('The name of the user-assigned managed identity to be used by the function app.')
param managedIdentityName string

@description('The name of the Storage Account')
param storageAccountName string = toLower('funcsa${uniqueString(resourceGroup().id)}')

@description('The ID of the tenant providing auth token')
param tenantID string = subscription().tenantId

@description('Optional. Resource ID of the app insight to leverage for this resource.')
param appInsightsResourceId string = ''

@description('The name of the function app as it appears in application insights')
param appInsightsCloudRoleName string = functionAppName

@description('Flag to indicate site exists. If true, the module will preserve the existing appsettings for the site.')
param resourceExists bool = true


var roleName = 'app_only'
var roleId = guid(roleName, functionAppName)
resource appReg 'Microsoft.Graph/applications@v1.0' = {
  displayName: functionAppName
  uniqueName: functionAppName
  identifierUris: [
    'api://${functionAppName}'
  ]
  appRoles: [
    {
      allowedMemberTypes: [
        'Application'
      ]
      description: 'Service-to-Service access'
      displayName: roleName
      id: roleId
      isEnabled: true
      value: 'app_only_access'
    }
  ]
}

resource appRegServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: appReg.appId
  appRoleAssignmentRequired: true
}

resource appRoleAssignments 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for principalId in allowedPrincipalIds: {
  appRoleId: roleId
  principalId: principalId
  resourceId: appRegServicePrincipal.id
}]


resource internalApiManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: managedIdentityName
}

var requiredAppsettings = {
  AzureWebJobsFeatureFlags: 'EnableHttpProxying'
  FUNCTIONS_EXTENSION_VERSION: '~4'
  FUNCTIONS_WORKER_RUNTIME: 'dotnet-isolated'
  WEBSITE_CLOUD_ROLENAME: appInsightsCloudRoleName
  // note: ideally, WEBSITE_CONTENTAZUREFILECONNECTIONSTRING should be set by the module - see ote on setWebsiteContentAzureFileConnectionString
  WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
  WEBSITE_CONTENTSHARE: toLower(functionAppName)
  WEBSITE_RUN_FROM_PACKAGE: '1'
}

var existingAppsettings = resourceExists ? list(resourceId('Microsoft.Web/sites/config', functionAppName, 'appsettings'), '2020-12-01').properties : {}

// module should ideally assign WEBSITE_CONTENTAZUREFILECONNECTIONSTRING using a param value setWebsiteContentAzureFileConnectionString
module functionApp 'br/public:avm/res/web/site:0.2.0' = {
  name: '${uniqueString(deployment().name, location)}-InternalApi'
  params:{
    name: functionAppName
    kind: 'functionapp'
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        internalApiManagedId.id
      ]
    }
    appInsightResourceId: appInsightsResourceId
    appSettingsKeyValuePairs: union(requiredAppsettings, existingAppsettings)
    setAzureWebJobsDashboard: false
    // setWebsiteContentAzureFileConnectionString: true
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      cors: {
        allowedOrigins: corsAllowedOrigins
        supportCredentials: corsSupportCredentials
      }
      http20Enabled: true
    }
    storageAccountResourceId: storageAccount.id
    clientAffinityEnabled: false
    authSettingV2Configuration: {
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
            clientId: appReg.appId
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
    serverFarmResourceId: hostingPlan.outputs.resourceId
  }
}

module hostingPlan 'br/public:avm/res/web/serverfarm:0.1.0' = {
  name: '${uniqueString(deployment().name, location)}-HostingPlan'
  params:{
    name: functionAppName
    kind: 'FunctionApp'
    sku: {
      name: 'Y1'
      tier: 'Dynamic'
      size: 'Y1'
      family: 'Y'
      capacity: 0
    }
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' existing = {
  name: storageAccountName
}

@description('The Client ID of the Azure AD application associated with the internal api managed identity.')
output internalApiManagedIdentityClientId string = internalApiManagedId.properties.clientId
