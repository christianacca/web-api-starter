@description('The name of the logical server.')
param serverName string = '${resourceGroup().name}-sql'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The name of the Azure AD admin for the SQL server.')
param aadAdminName string

@description('The Object ID of the Azure AD admin.')
param aadAdminObjectId string

@allowed([
  'User'
  'Group'
  'Application'
])
param aadAdminType string = 'User'

@description('The name of the sql db.')
param databaseName string

@description('The name of the user-assigned managed identity.')
param managedIdentityName string

@description('The firewall rules to configure access to the SQL server')
param firewallRules array = []

@description('Optional. The failover server to configure.')
param failoverInfo serverType?

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

var admin = {
  login: aadAdminName
  sid: aadAdminObjectId
  principalType: aadAdminType
  azureADOnlyAuthentication: true
}

var managedId = {
  userAssignedResourceIds: [
    managedIdentity.id
  ]
}

module server 'br/public:avm/res/sql/server:0.1.4' = {
  name: '${serverName}Deployment'
  params: {
    name: serverName
    location: location
    primaryUserAssignedIdentityId: managedIdentity.id
    managedIdentities: managedId
    administrators: admin
    firewallRules: firewallRules
    databases: [
      {
        name: databaseName
        skuName: 'Standard'
        skuTier: 'Standard'
        maxSizeBytes: 268435456000
        requestedBackupStorageRedundancy: 'Geo'
      }
    ]
  }
}

var failoverServerName = failoverInfo != null ? failoverInfo!.serverName : ''

module failoverServer 'br/public:avm/res/sql/server:0.1.4' = if (failoverInfo != null) {
  name: '${failoverServerName}Deployment'
  params: {
    name: failoverServerName
    location: failoverInfo != null ? failoverInfo!.location : ''
    primaryUserAssignedIdentityId: managedIdentity.id
    managedIdentities: managedId
    administrators: admin
    firewallRules: firewallRules
  }
}

resource server_failoverGroup 'Microsoft.Sql/servers/failoverGroups@2021-05-01-preview' = if (failoverInfo != null) {
  name: '${serverName}/${databaseName}-fg'
  properties: {
    partnerServers: [
      {
        id: resourceId('Microsoft.Sql/servers', failoverServerName)
      }
    ]
    readWriteEndpoint: {
      failoverPolicy: 'Automatic'
      failoverWithDataLossGracePeriodMinutes: 60
    }
    readOnlyEndpoint: {
      failoverPolicy: 'Disabled'
    }
    databases: [
      resourceId('Microsoft.Sql/servers/databases', serverName, databaseName)
    ]
  }
  dependsOn: [
    failoverServer
    server
  ]
}

@description('The ID of the Azure AD application associated with the managed identity.')
output managedIdentityClientId string = managedIdentity.properties.clientId

// =============== //
//   Definitions   //
// =============== //

type serverType = {
  @description('Required. The name of the server.')
  serverName: string

  @description('Required. Location for this server and child resources.')
  location: string
}?
