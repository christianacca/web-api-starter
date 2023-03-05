#disable-next-line no-hardcoded-env-urls
@description('Relative DNS name for the traffic manager profile, resulting FQDN will be <uniqueDnsName>.trafficmanager.net, must be globally unique.')
param uniqueDnsName string

@description('The endpoint path to route request from traffic manager')
param path string

@description('The name of the primary endpoint')
param primaryEndpointName string = 'primary'

@description('The primary external endpoint to monitor')
param primaryEndpointHostName string

@description('The loction to send requests from to the primary endpoint')
param primaryEndpointLocation string

@description('The name of the secondary endpoint')
param secondaryEndpointName string = 'primary'

@description('The secondary external endpoint to monitor')
param secondaryEndpointHostName string

@description('The location to send requests from to the secondary endpoint')
param secondaryEndpointLocation string

resource profile 'Microsoft.Network/trafficmanagerprofiles@2018-08-01' = {
  name: uniqueDnsName
  location: 'global'
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: 'Performance'
    dnsConfig: {
      relativeName: uniqueDnsName
      ttl: 60
    }
    monitorConfig: {
      protocol: 'HTTP'
      port: 80
      path: path
    }
    endpoints: [
      {
        type: 'Microsoft.Network/TrafficManagerProfiles/ExternalEndpoints'
        name: primaryEndpointName
        properties: {
          target: primaryEndpointHostName
          endpointStatus: 'Enabled'
          endpointLocation: primaryEndpointLocation
        }
      }
      {
        type: 'Microsoft.Network/TrafficManagerProfiles/ExternalEndpoints'
        name: secondaryEndpointName
        properties: {
          target: secondaryEndpointHostName
          endpointStatus: 'Enabled'
          endpointLocation: secondaryEndpointLocation
        }
      }
    ]
  }
}
