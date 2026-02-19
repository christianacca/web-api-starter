param instanceSettings object
param sharedSettings sharedSettingsType

var location = instanceSettings.ResourceLocation

// todo: switch to azure verified module once keyvault certificate integration is supported for failover (see https://github.com/Azure/bicep-registry-modules/issues/5145)

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = if (!empty(sharedSettings.logAnalyticsWorkspaceResourceId)) {
  name: last(split(sharedSettings.logAnalyticsWorkspaceResourceId, '/'))!
  scope: resourceGroup(split(sharedSettings.logAnalyticsWorkspaceResourceId, '/')[2], split(sharedSettings.logAnalyticsWorkspaceResourceId, '/')[4])
}

var kvSettings = sharedSettings.certSettings.KeyVault
resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: kvSettings.ResourceName
  scope: resourceGroup((kvSettings.SubscriptionId ?? subscription().subscriptionId), kvSettings.ResourceGroupName)

  resource cert 'secrets' existing = { name: sharedSettings.certSettings.ResourceName }
}

resource acaEnv 'Microsoft.App/managedEnvironments@2023-11-02-preview' = {
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
        customerId: logAnalyticsWorkspace.?properties.customerId
        #disable-next-line BCP422
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
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