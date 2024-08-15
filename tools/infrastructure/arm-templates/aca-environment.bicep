param instanceSettings object
param sharedSettings sharedSettingsType

var location = instanceSettings.ResourceLocation

// todo: switch to azure verified module once keyvault certificate integration is supported (see https://github.com/Azure/bicep-registry-modules/pull/2719)

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
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    customDomainConfiguration: {
      certificateKeyVaultProperties: {
        identity: sharedSettings.managedIdentityResourceId
        keyVaultUrl: kv::cert.properties.secretUri
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
}

output defaultDomain string = acaEnv.properties.defaultDomain
output resourceId string = acaEnv.id


// =============== //
//   Definitions   //
// =============== //


type sharedSettingsType = {
  certSettings: object
  managedIdentityResourceId: string
  logAnalyticsWorkspaceResourceId: string
}
