@description('The Client ID of the Internal Api AAD app registration.')
param internalApiClientId string

@description('Whether the Internal Api function app already exists.')
param internalApiExists bool = true

@description('Whether the failover intance of the API container app already exists.')
param apiFailoverExists bool = true

@description('Whether the primary intance of the API container app already exists.')
param apiPrimaryExists bool = true

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
    appName: settings.Product.Abbreviation
    defaultAvailabilityTests: [
      settings.SubProducts.ApiAvailabilityTest
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

resource acaEnvManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: settings.SubProducts.Aca.ManagedIdentity
  location: location
}

var certSettings = settings.TlsCertificates.Current
// module acaEnvCertPermission 'keyvault-role-assignment.bicep' = {
//   name: '${uniqueString(deployment().name, location)}-AcaEnvCertPermission'
//   scope: resourceGroup((certSettings.KeyVault.SubscriptionId ?? subscription().subscriptionId), certSettings.KeyVault.ResourceGroupName)
//   params: {
//     resourceName: certSettings.KeyVault.ResourceName
//     principalId: acaEnvManagedId.properties.principalId
//     roleDefinitionId: 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba' // 'Key Vault Certificate User'
//   }
// }

resource apiManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: settings.SubProducts.Api.ManagedIdentity.Primary
  location: location
}

resource apiAcrPullManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: settings.SubProducts.Api.ManagedIdentity.AcrPull
  location: location
}

// dev and prod container registries can be the same instance, therefore we use union to de-dup references to same registry
var containerRegistries = union(settings.ContainerRegistries.Available, [])
module acrPullPermissions 'acr-role-assignment.bicep' = [for (registry, index) in containerRegistries: {
  name: '${uniqueString(deployment().name, location)}-${index}-AcrPullPermission'
  scope: resourceGroup((registry.SubscriptionId ?? subscription().subscriptionId), registry.ResourceGroupName)
  params: {
    principalId: apiAcrPullManagedId.properties.principalId
    registryName: registry.ResourceName
    roleDefinitionId: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // 'AcrPull'
  }
}]

var acaEnvSharedSettings = {
  certSettings: settings.TlsCertificates.Current
  logAnalyticsWorkspaceResourceId: azureMonitor.outputs.logAnalyticsWorkspaceResourceId
  managedIdentityResourceId: acaEnvManagedId.id
}

module acaEnvPrimary 'aca-environment.bicep' = {
  name: '${uniqueString(deployment().name, location)}-AcaEnvPrimary'
  params: {
    instanceSettings: settings.SubProducts.Aca.Primary
    sharedSettings: acaEnvSharedSettings
  }
  // dependsOn: [acaEnvCertPermission]
}

var acaContainerRegistries = map(containerRegistries, registry => ({
  server: '${registry.ResourceName}.azurecr.io'
  identity: apiAcrPullManagedId.id
}))

var apiSharedSettings = {
  appInsightsConnectionString: azureMonitor.outputs.appInsightsConnectionString
  certSettings: settings.TlsCertificates.Current
  managedIdentityClientIds: {
    default: apiManagedId.properties.clientId
  }
  managedIdentityResourceIds: [
    apiManagedId.id
    apiAcrPullManagedId.id
  ]
  registries: acaContainerRegistries
  subProductsSettings: settings.SubProducts
}

module apiPrimary 'api.bicep' = {
  name: '${uniqueString(deployment().name, location)}-AcaApiPrimary'
  params: {
    exists: apiPrimaryExists
    instanceSettings: settings.SubProducts.Api.Primary
    sharedSettings: apiSharedSettings
  }
  dependsOn: [acaEnvPrimary]
}

var hasAcaFailover = !empty(settings.SubProducts.Aca.Failover ?? {})
module acaEnvFailover 'aca-environment.bicep' = if (hasAcaFailover) {
  name: '${uniqueString(deployment().name, location)}-AcaEnvFailover'
  params: {
    instanceSettings: settings.SubProducts.Aca.Failover
    sharedSettings: acaEnvSharedSettings
  }
  // dependsOn: [acaEnvCertPermission]
}

module apiFailover 'api.bicep' = if (!empty(settings.SubProducts.Api.Failover ?? {})) {
  name: '${uniqueString(deployment().name, location)}-AcaApiFailover'
  params: {
    instanceSettings: settings.SubProducts.Api.Failover
    exists: apiFailoverExists
    sharedSettings: apiSharedSettings
  }
  dependsOn: hasAcaFailover ? [acaEnvFailover] : []
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

var apiPrimaryDomain = acaEnvPrimary.outputs.defaultDomain
var apiFailoverDomain = !empty(settings.SubProducts.Aca.Failover ?? {}) ? acaEnvFailover.outputs.defaultDomain : ''
var apiTmEndpoints = map(settings.SubProducts.ApiTrafficManager.Endpoints, endpoint => ({ 
  ...endpoint
  Target: replace(endpoint.Target, 'ACA_ENV_DEFAULT_DOMAIN', endpoint.Name == settings.SubProducts.Api.Primary.ResourceName ? apiPrimaryDomain : apiFailoverDomain )
}))

module apiTrafficManager 'traffic-manager-profile.bicep' = {
  name: '${uniqueString(deployment().name, location)}-ApiTrafficManager'
  params: {
    tmSettings: {
      ...settings.SubProducts.ApiTrafficManager
      Endpoints: apiTmEndpoints
    }
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
output apiManagedIdentityClientId string = apiManagedId.properties.clientId
@description('The Client ID of the Azure AD application associated with the internal api managed identity.')
output internalApiManagedIdentityClientId string = internalApi.outputs.internalApiManagedIdentityClientId
@description('The Client ID of the Azure AD application associated with the sql managed identity.')
output sqlManagedIdentityClientId string = azureSqlDb.outputs.managedIdentityClientId
