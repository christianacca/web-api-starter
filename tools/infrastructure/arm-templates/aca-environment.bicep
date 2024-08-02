param instanceSettings object
param logAnalyticsWorkspaceResourceId string

var location = instanceSettings.ResourceLocation

module acaEnv 'br/public:avm/res/app/managed-environment:0.5.2' = {
  name: '${uniqueString(deployment().name, location)}-AcaEnv'
  params: {
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    location: location
    name: instanceSettings.ResourceName
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
