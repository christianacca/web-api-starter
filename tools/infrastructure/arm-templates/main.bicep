@description('The Client ID of the Internal Api AAD app registration.')
param internalApiClientId string

@description('Whether the Internal Api function app already exists.')
param internalApiExists bool = true

param location string = resourceGroup().location

@description('The settings for all resources provisioned by this template.')
param settings object

@description('The Object ID of the SQL AAD Admin security group.')
param sqlAdAdminGroupObjectId string


var kvSettings = settings.SubProducts.KeyVault
module keyVault 'br/public:avm/res/key-vault/vault:0.6.2' = {
  name: '${uniqueString(deployment().name, location)}-KeyVault'
  params: {
    name: kvSettings.ResourceName
    enableRbacAuthorization: true
    enablePurgeProtection: kvSettings.EnablePurgeProtection
    softDeleteRetentionInDays: 90
    sku: 'standard'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    roleAssignments: [
      { principalId: internalApiManagedId.properties.principalId, roleDefinitionIdOrName: 'Key Vault Secrets User', principalType: 'ServicePrincipal' }
      { principalId: apiManagedId.properties.principalId, roleDefinitionIdOrName: 'Key Vault Secrets User', principalType: 'ServicePrincipal' }
    ]
  }
}

var aiSettings = settings.SubProducts.AppInsights
module azureMonitor 'azure-monitor.bicep' = {
  name: '${uniqueString(deployment().name, location)}-AzureMonitor'
  params: {
    alertEmailCritical: settings.IsEnvironmentProdLike ? 'christian.crowhurst@gmail.com' : 'christian.crowhurst@gmail.com'
    alertEmailNonCritical: settings.IsEnvironmentProdLike ? 'christian.crowhurst@gmail.com' : 'christian.crowhurst@gmail.com'
    appInsightsName: aiSettings.ResourceName
    appName: settings.ProductName
    defaultAvailabilityTests: [
      settings.SubProducts.ApiAvailabilityTest
      settings.SubProducts.WebAvailabilityTest
    ]
    enableMetricAlerts: aiSettings.IsMetricAlertsEnabled
    environmentName: settings.EnvironmentName
    environmentAbbreviation: aiSettings.EnvironmentAbbreviation
    location: location
    workspaceName: aiSettings.WorkspaceName
  }
}

var reportStorage = settings.SubProducts.PbiReportStorage
module pbiReportStorage 'br/public:avm/res/storage/storage-account:0.11.0' = {
  name: '${uniqueString(deployment().name, location)}-PbiReportStorage'
  params: {
    name: reportStorage.StorageAccountName
    skuName: reportStorage.StorageAccountType
    accessTier: reportStorage.DefaultStorageTier
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    blobServices: {
      changeFeedEnabled: true
      changeFeedRetentionInDays: 95
      restorePolicyEnabled: true
      restorePolicyDays: 90
      containerDeleteRetentionPolicyDays: 90
      deleteRetentionPolicyDays: 95
      isVersioningEnabled: true
    }
    managementPolicyRules: [
      {
        definition: {
          actions: {
            version: {
              delete: {
                daysAfterCreationGreaterThan: 90
              }
            }
          }
          filters: {
            blobTypes: [
              'blockBlob'
            ]
          }
        }
        enabled: true
        name: 'retention-lifecyle'
        type: 'Lifecycle'
      }
    ]
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    // note: if you have an old storage account you might need to uncomment this if it's already false:
//     requireInfrastructureEncryption: false
    roleAssignments: [
      { principalId: internalApiManagedId.properties.principalId, roleDefinitionIdOrName: 'Storage Blob Data Contributor', principalType: 'ServicePrincipal' }
    ]
  }
}

resource apiManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: settings.SubProducts.Api.ManagedIdentity
  location: location
}

resource internalApiManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: settings.SubProducts.InternalApi.ManagedIdentity
  location: location
}

module internalApiStorageAccount 'br/public:avm/res/storage/storage-account:0.11.0' = {
  name: '${uniqueString(deployment().name, location)}-FunctionsStorageAccount'
  params: {
    name: settings.SubProducts.InternalApi.StorageAccountName
    kind: 'Storage'
    skuName: 'Standard_LRS'
    blobServices: {}
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    queueServices: {
      queues: [
        { name: 'default-queue' }
        { name: 'default-queue-poison' }
      ]
    }
    roleAssignments: [
      { principalId: internalApiManagedId.properties.principalId, roleDefinitionIdOrName: 'Storage Queue Data Message Processor', principalType: 'ServicePrincipal' }
      { principalId: apiManagedId.properties.principalId, roleDefinitionIdOrName: 'Storage Queue Data Message Sender', principalType: 'ServicePrincipal' }
    ]
  }
}

var internalApiSettings = settings.SubProducts.InternalApi
module internalApi 'internal-api.bicep' = {
  name: '${uniqueString(deployment().name, location)}-InternalApi'
  params: {
    appClientId: internalApiClientId
    appInsightsCloudRoleName: 'Web API Starter Functions'
    appInsightsResourceId: azureMonitor.outputs.appInsightsResourceId
    functionAppName: internalApiSettings.ResourceName
    managedIdentityName: internalApiSettings.ManagedIdentity
    location: location
    resourceExists: internalApiExists
    storageAccountName: internalApiStorageAccount.outputs.name
  }
}

var tmpSettings = [
  settings.SubProducts.ApiTrafficManager
  settings.SubProducts.WebTrafficManager
]
module trafficManagerProfiles 'br/public:network/traffic-manager:2.3.3' = [for (tmProfile, i) in tmpSettings: {
  name: '${uniqueString(deployment().name, location)}-${i}-TrafficManager'
  params: {
    name: tmProfile.ResourceName
    trafficManagerDnsName: tmProfile.ResourceName
    ttl: 60
    monitorConfig: {
      protocol: 'HTTP'
      port: 80
      path: tmProfile.TrafficManagerPath
      expectedStatusCodeRanges: null // defaults to 200
    }
    endpoints: tmProfile.Endpoints
  }
}]


var sqlServer = settings.SubProducts.Sql
var sqlDatabase = settings.SubProducts.Db
var failoverInfo = !empty(sqlServer.Failover) ? { 
  serverName: sqlServer.Failover.ResourceName
  location: sqlServer.Failover.ResourceLocation
} : null

module azureSqlDb 'azure-sql-server.bicep' = {
  name: '${uniqueString(deployment().name, location)}-AzureSqlDb'
  params: {
    serverName: sqlServer.Primary.ResourceName
    aadAdminName: sqlServer.AadAdminGroupName
    aadAdminObjectId: sqlAdAdminGroupObjectId
    aadAdminType: 'Group'
    firewallRules: sqlServer.Firewall.Rule
    location: location
    databaseName: sqlDatabase.ResourceName
    managedIdentityName: sqlServer.ManagedIdentity
    failoverInfo: failoverInfo
  }
}

@description('The Client ID of the Azure AD application associated with the api managed identity.')
output apiManagedIdentityClientId string = apiManagedId.properties.clientId
@description('The Client ID of the Azure AD application associated with the internal api managed identity.')
output internalApiManagedIdentityClientId string = internalApi.outputs.internalApiManagedIdentityClientId
@description('The Client ID of the Azure AD application associated with the sql managed identity.')
output sqlManagedIdentityClientId string = azureSqlDb.outputs.managedIdentityClientId
