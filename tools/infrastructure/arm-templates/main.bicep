@description('Whether the failover intance of the API container app already exists.')
param apiFailoverExists bool = true

@description('Whether the primary intance of the API container app already exists.')
param apiPrimaryExists bool = true

@description('Whether the failover intance of the MVC App container app already exists.')
param appFailoverExists bool = true

@description('Whether the primary intance of the MVC App container app already exists.')
param appPrimaryExists bool = true

param location string = resourceGroup().location

@description('The settings for all resources provisioned by this template. TIP: to find the structure of settings object use: ./tools/infrastructure/get-product-conventions.ps1')
param settings object

@description('The Object ID of the SQL AAD Admin security group.')
param sqlAdAdminGroupObjectId string

import { objectValues } from 'utils.bicep'


var kvSettings = settings.SubProducts.KeyVault
module keyVault 'br/public:avm/res/key-vault/vault:0.11.0' = {
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
      { principalId: appManagedId.properties.principalId, roleDefinitionIdOrName: 'Key Vault Secrets User', principalType: 'ServicePrincipal' }
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
    defaultAvailabilityTests: filter(objectValues(settings.SubProducts), x => x.Type == 'AvailabilityTest')
    enableMetricAlerts: aiSettings.IsMetricAlertsEnabled
    environmentName: settings.EnvironmentName
    environmentAbbreviation: aiSettings.EnvironmentAbbreviation
    location: location
    workspaceName: aiSettings.WorkspaceName
  }
}

var reportStorage = settings.SubProducts.PbiReportStorage
module pbiReportStorage 'br/public:avm/res/storage/storage-account:0.14.3' = {
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
module acaEnvCertPermission 'keyvault-cert-role-assignment.bicep' = if (settings.SubProducts.Aca.IsCustomDomainEnabled) {
  name: '${uniqueString(deployment().name, location)}-AcaEnvCertPermission'
  scope: resourceGroup((certSettings.KeyVault.SubscriptionId ?? subscription().subscriptionId), certSettings.KeyVault.ResourceGroupName)
  params: {
    certificateName: certSettings.ResourceName
    keyVaultName: certSettings.KeyVault.ResourceName
    principalId: acaEnvManagedId.properties.principalId
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6' // 'Key Vault Secrets User'
  }
}

resource acrPullManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: settings.SubProducts.AcrPull.ResourceName
  location: location
}

// dev and prod container registries can be the same instance, therefore we use union to de-dup references to same registry
var containerRegistries = union(settings.ContainerRegistries.Available, [])
module acrPullPermissions 'acr-role-assignment.bicep' = [for (registry, index) in containerRegistries: {
  name: '${uniqueString(deployment().name, location)}-${index}-AcrPullPermission'
  scope: resourceGroup((registry.SubscriptionId ?? subscription().subscriptionId), registry.ResourceGroupName)
  params: {
    principalId: acrPullManagedId.properties.principalId
    resourceName: registry.ResourceName
    roleDefinitionId: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // 'AcrPull'
  }
}]


// ---------- Begin: ACA environments -----------

var acaEnvSharedSettings = {
  certSettings: settings.TlsCertificates.Current
  isCustomDomainEnabled: settings.SubProducts.Aca.IsCustomDomainEnabled
  logAnalyticsWorkspaceResourceId: azureMonitor.outputs.logAnalyticsWorkspaceResourceId
  managedIdentityResourceId: acaEnvManagedId.id
}

module acaEnvPrimary 'aca-environment.bicep' = {
  name: '${uniqueString(deployment().name, location)}-AcaEnvPrimary'
  params: {
    instanceSettings: settings.SubProducts.Aca.Primary
    sharedSettings: acaEnvSharedSettings
  }
  dependsOn: acaEnvSharedSettings.isCustomDomainEnabled ? [acaEnvCertPermission] : []
}

var hasAcaFailover = !empty(settings.SubProducts.Aca.Failover ?? {})
module acaEnvFailover 'aca-environment.bicep' = if (hasAcaFailover) {
  name: '${uniqueString(deployment().name, location)}-AcaEnvFailover'
  params: {
    instanceSettings: settings.SubProducts.Aca.Failover
    sharedSettings: acaEnvSharedSettings
  }
  dependsOn: acaEnvSharedSettings.isCustomDomainEnabled ? [acaEnvCertPermission] : []
}

var acaPrimaryDomain = acaEnvPrimary.outputs.defaultDomain
var acaFailoverDomain = !empty(settings.SubProducts.Aca.Failover ?? {}) ? acaEnvFailover.outputs.defaultDomain : ''

// ---------- End: ACA environments -----------


var acaContainerRegistries = map(containerRegistries, registry => ({
  server: '${registry.ResourceName}.azurecr.io'
  identity: acrPullManagedId.id
}))


// ---------- Begin: Template.Api -----------

resource apiManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: settings.SubProducts.Api.ManagedIdentity.Primary
  location: location
}

var apiSharedSettings = {
  appInsightsConnectionString: azureMonitor.outputs.appInsightsConnectionString
  certSettings: settings.TlsCertificates.Current
  isCustomDomainEnabled: settings.SubProducts.Aca.IsCustomDomainEnabled
  managedIdentityClientIds: {
    default: apiManagedId.properties.clientId
  }
  managedIdentityResourceIds: [
    apiManagedId.id
    acrPullManagedId.id
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

module apiFailover 'api.bicep' = if (!empty(settings.SubProducts.Api.Failover ?? {})) {
  name: '${uniqueString(deployment().name, location)}-AcaApiFailover'
  params: {
    instanceSettings: settings.SubProducts.Api.Failover
    exists: apiFailoverExists
    sharedSettings: apiSharedSettings
  }
  dependsOn: hasAcaFailover ? [acaEnvFailover] : []
}

var apiTmEndpoints = map(settings.SubProducts.ApiTrafficManager.Endpoints, endpoint => ({ 
  ...endpoint
  Target: replace(endpoint.Target, 'ACA_ENV_DEFAULT_DOMAIN', endpoint.Name == settings.SubProducts.Api.Primary.ResourceName ? acaPrimaryDomain : acaFailoverDomain )
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

// ---------- End: Template.Api -----------


// ---------- Begin: Template.App -----------

resource appManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: settings.SubProducts.App.ManagedIdentity.Primary
  location: location
}

var appSharedSettings = {
  appInsightsConnectionString: azureMonitor.outputs.appInsightsConnectionString
  certSettings: settings.TlsCertificates.Current
  isCustomDomainEnabled: settings.SubProducts.Aca.IsCustomDomainEnabled
  managedIdentityClientIds: {
    default: appManagedId.properties.clientId
  }
  managedIdentityResourceIds: [
    appManagedId.id
    acrPullManagedId.id
  ]
  registries: acaContainerRegistries
  subProductsSettings: settings.SubProducts
}

module appPrimary 'app.bicep' = {
  name: '${uniqueString(deployment().name, location)}-AcaAppPrimary'
  params: {
    exists: appPrimaryExists
    instanceSettings: settings.SubProducts.App.Primary
    sharedSettings: appSharedSettings
  }
  dependsOn: [acaEnvPrimary]
}

module appFailover 'app.bicep' = if (!empty(settings.SubProducts.App.Failover ?? {})) {
  name: '${uniqueString(deployment().name, location)}-AcaAppFailover'
  params: {
    instanceSettings: settings.SubProducts.App.Failover
    exists: appFailoverExists
    sharedSettings: appSharedSettings
  }
  dependsOn: hasAcaFailover ? [acaEnvFailover] : []
}

var appTmEndpoints = map(settings.SubProducts.AppTrafficManager.Endpoints, endpoint => ({ 
  ...endpoint
  Target: replace(endpoint.Target, 'ACA_ENV_DEFAULT_DOMAIN', endpoint.Name == settings.SubProducts.App.Primary.ResourceName ? acaPrimaryDomain : acaFailoverDomain )
}))

module appTrafficManager 'traffic-manager-profile.bicep' = {
  name: '${uniqueString(deployment().name, location)}-AppTrafficManager'
  params: {
    tmSettings: {
      ...settings.SubProducts.AppTrafficManager
      Endpoints: appTmEndpoints
    }
  }
}

// ---------- End: Template.App -----------


resource internalApiManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: settings.SubProducts.InternalApi.ManagedIdentity
  location: location
}

module internalApiStorageAccount 'br/public:avm/res/storage/storage-account:0.14.3' = {
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
    allowedPrincipalIds: [apiManagedId.properties.principalId]
    appInsightsCloudRoleName: 'Web API Starter Functions'
    appInsightsResourceId: azureMonitor.outputs.appInsightsResourceId
    functionAppName: internalApiSettings.ResourceName
    managedIdentityResourceIds: [
      internalApiManagedId.id
    ]
    location: location
    storageAccountName: internalApiStorageAccount.outputs.name
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
@description('The Client ID of the Azure AD application associated with the app managed identity.')
output appManagedIdentityClientId string = appManagedId.properties.clientId
@description('The Client ID of the Azure AD application associated with the internal api managed identity.')
output internalApiManagedIdentityClientId string = internalApiManagedId.properties.clientId
@description('The Client ID of the Azure AD application associated with the sql managed identity.')
output sqlManagedIdentityClientId string = azureSqlDb.outputs.managedIdentityClientId
