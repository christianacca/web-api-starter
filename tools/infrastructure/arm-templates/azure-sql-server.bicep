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

import { firewallRuleType } from 'br/public:avm/res/sql/server:0.11.1'
@description('The firewall rules to configure access to the SQL server')
param firewallRules firewallRuleType[]

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

module server 'br/public:avm/res/sql/server:0.11.1' = {
  name: '${serverName}Deployment'
  params: {
    name: serverName
    location: location
    databases: [
      {
        name: databaseName
        sku: {
          name: 'Standard'
          tier: 'Standard'
        }
        maxSizeBytes: 268435456000
        requestedBackupStorageRedundancy: 'Geo'
        zoneRedundant: false
      }
    ]
    // begin: shared settings - keep in sync with failover server definition below
    primaryUserAssignedIdentityId: managedIdentity.id
    managedIdentities: managedId
    administrators: admin
    firewallRules: firewallRules
    auditSettings: { state: 'Disabled' }
    // end: shared settings - keep in sync with failover server definition below
  }
}

var failoverServerName = failoverInfo != null ? failoverInfo!.serverName : ''

module failoverServer 'br/public:avm/res/sql/server:0.11.1' = if (failoverInfo != null) {
  name: '${failoverServerName}Deployment'
  params: {
    name: failoverServerName
    location: failoverInfo != null ? failoverInfo!.location : ''
    // begin: shared settings - keep in sync with primary server definition above
    primaryUserAssignedIdentityId: managedIdentity.id
    managedIdentities: managedId
    administrators: admin
    firewallRules: firewallRules
    auditSettings: { state: 'Disabled' }
    // end: shared settings - keep in sync with primary server definition above
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
