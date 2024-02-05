@description('The Client ID of the Internal Api AAD app registration.')
param internalApiClientId string

param location string = resourceGroup().location

@description('The settings for all resources provisioned by this template.')
param settings object

@description('The Object ID of the SQL AAD Admin security group.')
param sqlAdAdminGroupObjectId string

var kvSettings = settings.SubProducts.KeyVault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: kvSettings.ResourceName
  location: location
  properties: {
    enableRbacAuthorization: true
    enablePurgeProtection: kvSettings.EnablePurgeProtection == false ? null : true
    softDeleteRetentionInDays: 90
    tenantId: subscription().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
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
    enableMetricAlerts: aiSettings.IsMetricAlertsEnabled
    environmentName: settings.EnvironmentName
    environmentAbbreviation: aiSettings.EnvironmentAbbreviation
    location: location
    workspaceName: aiSettings.WorkspaceName
  }
}

var apiSettings = settings.SubProducts.Api
module apiManagedIdentity 'api-managed-identity.bicep' = {
  name: '${uniqueString(deployment().name, location)}-ApiManagedIdentity'
  params: {
    aksCluster: settings.Aks.Primary.ResourceName
    aksClusterResourceGroup: settings.Aks.Primary.ResourceGroupName
    aksServiceAccountName: apiSettings.ServiceAccountName
    aksServiceAccountNamespace: settings.Aks.Namespace
    location: location
    managedIdentityName: apiSettings.ManagedIdentity
  }
}

var reportStorage = settings.SubProducts.PbiReportStorage
module pbiReportStorage 'storage-account.bicep' = {
  name: '${uniqueString(deployment().name, location)}-PbiReportStorage'
  params: {
    defaultStorageTier: reportStorage.DefaultStorageTier
    location: location
    storageAccountName: reportStorage.StorageAccountName
    storageAccountType: reportStorage.StorageAccountType
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


var internalApiSettings = settings.SubProducts.InternalApi
module internalApi 'internal-api.bicep' = {
  name: '${uniqueString(deployment().name, location)}-InternalApi'
  params: {
    appClientId: internalApiClientId
    appInsightsCloudRoleName: 'Web API Starter Functions'
    appInsightsResourceId: azureMonitor.outputs.appInsightsResourceId
    deployDefaultStorageQueue: true
    functionAppName: internalApiSettings.ResourceName
    managedIdentityName: internalApiSettings.ManagedIdentity
    location: location
    storageAccountName: internalApiSettings.StorageAccountName
  }
}

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
output apiManagedIdentityClientId string = apiManagedIdentity.outputs.clientId
@description('The Client ID of the Azure AD application associated with the internal api managed identity.')
output internalApiManagedIdentityClientId string = internalApi.outputs.internalApiManagedIdentityClientId
@description('The Client ID of the Azure AD application associated with the sql managed identity.')
output sqlManagedIdentityClientId string = azureSqlDb.outputs.managedIdentityClientId
