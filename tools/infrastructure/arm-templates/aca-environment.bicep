param instanceSettings object
param sharedSettings sharedSettingsType

var location = instanceSettings.ResourceLocation

var kvSettings = sharedSettings.certSettings.KeyVault
resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: kvSettings.ResourceName
  scope: resourceGroup((kvSettings.SubscriptionId ?? subscription().subscriptionId), kvSettings.ResourceGroupName)

  resource cert 'secrets' existing = { name: sharedSettings.certSettings.ResourceName }
}

var certificate = sharedSettings.isCustomDomainEnabled ? {
  certificateKeyVaultProperties: {
    identityResourceId: sharedSettings.managedIdentityResourceId
    keyVaultUrl: kv::cert.properties.secretUri
  }
  name: sharedSettings.certSettings.ResourceName  
} : {}

module acaEnv 'br/public:avm/res/app/managed-environment:0.10.2' = {
  name: '${uniqueString(deployment().name, location)}-AcaEnv'
  params: {
    name: instanceSettings.ResourceName
    certificate: certificate
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

output defaultDomain string = acaEnv.outputs.defaultDomain
output resourceId string = acaEnv.outputs.resourceId


// =============== //
//   Definitions   //
// =============== //


type sharedSettingsType = {
  certSettings: object
  isCustomDomainEnabled: bool
  managedIdentityResourceId: string
  logAnalyticsWorkspaceResourceId: string
}
