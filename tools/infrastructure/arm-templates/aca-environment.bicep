param instanceSettings object
param sharedSettings sharedSettingsType

var location = instanceSettings.ResourceLocation

var kvSettings = sharedSettings.certSettings.KeyVault
resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: kvSettings.ResourceName
  scope: resourceGroup((kvSettings.SubscriptionId ?? subscription().subscriptionId), kvSettings.ResourceGroupName)

  resource cert 'secrets' existing = { name: sharedSettings.certSettings.ResourceName }
}

module managedEnvironment 'br/public:avm/res/app/managed-environment:0.8.1' = {
  name: '${uniqueString(deployment().name, location)}-AcaEnv'
  params: {
    name: instanceSettings.ResourceName
    certificateKeyVaultProperties: {
      identityResourceId: sharedSettings.managedIdentityResourceId
      keyVaultUrl: kv::cert.properties.secretUri
    }
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        sharedSettings.managedIdentityResourceId
      ]
    }
    location: location
    logAnalyticsWorkspaceResourceId: sharedSettings.logAnalyticsWorkspaceResourceId
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: false
  }
}

output defaultDomain string = managedEnvironment.outputs.defaultDomain
output resourceId string = managedEnvironment.outputs.resourceId


// =============== //
//   Definitions   //
// =============== //


type sharedSettingsType = {
  certSettings: object
  managedIdentityResourceId: string
  logAnalyticsWorkspaceResourceId: string
}
