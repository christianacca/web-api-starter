extension microsoftGraphV1

@description('List of principal ids that are allowed to make http requests to the function app')
param allowedPrincipalIds string[] = []

@description('List of origins that should be allowed to make cross-origin\ncalls')
param corsAllowedOrigins string[] = []

@description('Specify whether CORS requests with credentials are allowed. See\nhttps://developer.mozilla.org/en-US/docs/Web/HTTP/CORS#Requests_with_credentials\nfor more details')
param corsSupportCredentials bool = false

@description('Specify the name of the function application')
param functionAppName string

@description('Specify the location for the function application resources')
param location string = resourceGroup().location

@description('A list of Resource ID of the user-assigned managed identities, in the form of /subscriptions/<subscriptionId>/resourceGroups/<ResourceGroupName>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<managedIdentity>.')
param managedIdentityResourceIds string[]

@description('The name of the Storage Account')
param storageAccountName string = toLower('funcsa${uniqueString(resourceGroup().id)}')

@description('The ID of the tenant providing auth token')
param tenantID string = subscription().tenantId

@description('Optional. Resource ID of the app insight to leverage for this resource.')
param appInsightsResourceId string = ''

@description('The name of the function app as it appears in application insights')
param appInsightsCloudRoleName string = functionAppName

var roleName = 'app_only'
var roleId = guid(roleName, functionAppName)
resource appReg 'Microsoft.Graph/applications@v1.0' = {
  displayName: functionAppName
  uniqueName: functionAppName
  identifierUris: [
    'api://${functionAppName}'
  ]
  appRoles: [
    // important: to delete a role, set it's `isEnabled` to false then deploy to all environments, only then can remove the role from the list
    // note: in the future, this may not be necessary see: https://github.com/microsoftgraph/msgraph-bicep-types/issues/197
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


module functionApp 'br/public:avm/res/web/site:0.21.0' = {
  name: '${uniqueString(deployment().name, location)}-InternalApi'
  params:{
    name: functionAppName
    kind: 'functionapp'
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: managedIdentityResourceIds
    }
    configs: [
      {
        name: 'appsettings'
        applicationInsightResourceId: appInsightsResourceId
        storageAccountResourceId: storageAccount.id
        properties: {
          // Disable the Application Insights agent/codeless attach - SDK is included directly in code instead
          ApplicationInsightsAgent_EXTENSION_VERSION: 'disabled'
          AzureWebJobsFeatureFlags: 'EnableHttpProxying'
          FUNCTIONS_EXTENSION_VERSION: '~4'
          FUNCTIONS_WORKER_RUNTIME: 'dotnet-isolated'
          WEBSITE_CLOUD_ROLENAME: appInsightsCloudRoleName
          WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
          WEBSITE_CONTENTSHARE: toLower(functionAppName)
          WEBSITE_RUN_FROM_PACKAGE: '1'
          WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED: '1'
        }
      }
      {
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
      }
    ]
    siteConfig: {
      netFrameworkVersion: 'v10.0'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: corsAllowedOrigins
        supportCredentials: corsSupportCredentials
      }
      http20Enabled: true
    }
    clientAffinityEnabled: false
    serverFarmResourceId: hostingPlan.outputs.resourceId
  }
}

module hostingPlan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: '${uniqueString(deployment().name, location)}-HostingPlan'
  params:{
    name: functionAppName
    kind: 'FunctionApp'
    skuName: 'Y1'
    skuCapacity: 0
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}
