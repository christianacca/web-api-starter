param tmSettings object

resource trafficManagerProfile 'Microsoft.Network/trafficmanagerprofiles@2022-04-01' = {
  name: tmSettings.ResourceName
  location: 'global'
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: 'Priority'
    dnsConfig: {
      relativeName: tmSettings.ResourceName
      ttl: 60
    }
    monitorConfig: {
      protocol: tmSettings.Protocol
      port: tmSettings.Port
      path: tmSettings.Path
      expectedStatusCodeRanges: null // defaults to 200
    }
    endpoints: map(tmSettings.Endpoints, ep => ({
      type: 'Microsoft.Network/TrafficManagerProfiles/ExternalEndpoints'
      name: ep.Name
      properties: {
        target: ep.Target
        endpointLocation: ep.EndpointLocation
        priority: ep.Priority
        alwaysServe: ep.AlwaysServe
      }
    }))
  }
}
