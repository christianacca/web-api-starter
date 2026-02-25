param instanceSettings object
param sharedSettings sharedSettingsType

var location = instanceSettings.ResourceLocation

// todo: switch to azure verified module once keyvault certificate integration is supported for failover (see https://github.com/Azure/bicep-registry-modules/issues/5145)

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: last(split(sharedSettings.logAnalyticsWorkspaceResourceId, '/'))!
  scope: resourceGroup(split(sharedSettings.logAnalyticsWorkspaceResourceId, '/')[2], split(sharedSettings.logAnalyticsWorkspaceResourceId, '/')[4])
}

var kvSettings = sharedSettings.certSettings.KeyVault
resource kv 'Microsoft.KeyVault/vaults@2025-05-01' existing = {
  name: kvSettings.ResourceName
  scope: resourceGroup((kvSettings.SubscriptionId ?? subscription().subscriptionId), kvSettings.ResourceGroupName)

  resource cert 'secrets' existing = { name: sharedSettings.certSettings.ResourceName }
}

resource acaEnv 'Microsoft.App/managedEnvironments@2025-10-02-preview' = {
  name: instanceSettings.ResourceName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${sharedSettings.managedIdentityResourceId}': {}
    }
  }
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    // Zone redundancy is free (no extra cost) but requires the environment to be deployed into a VNet,
    // which is not currently configured. Enabling it is also immutable - existing environments must be
    // recreated. Cross-region Traffic Manager failover provides region-level resilience in the interim.
    // todo: enable zone redundancy once infra is migrated to a VNet to support private endpoints for
    //       Azure SQL and Azure Storage - at that point set this to true and recreate all environments.
    zoneRedundant: false
  }

  resource acaEnvCert 'certificates' = if (sharedSettings.isCustomDomainEnabled) {
    name: sharedSettings.certSettings.ResourceName
    location: location
    properties: {
      certificateKeyVaultProperties: {
        identity: sharedSettings.managedIdentityResourceId
        keyVaultUrl: kv::cert.properties.secretUri
      }
    }
  }
}

output defaultDomain string = acaEnv.properties.defaultDomain
output resourceId string = acaEnv.id


// =============== //
//   Definitions   //
// =============== //


type sharedSettingsType = {
  certSettings: object
  isCustomDomainEnabled: bool
  managedIdentityResourceId: string
  logAnalyticsWorkspaceResourceId: string
}
