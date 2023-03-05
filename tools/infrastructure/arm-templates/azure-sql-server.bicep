@description('The name of the logical server.')
param serverName string = '${resourceGroup().name}-sql'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The name of the Azure AD admin for the SQL server.')
param aadAdminName string

@description('The Object ID of the Azure AD admin.')
param aadAdminObjectId string

@description('The Tenant ID of the Azure Active Directory')
param aadAdminTenantId string = subscription().tenantId

@allowed([
  'User'
  'Group'
  'Application'
])
param aadAdminType string = 'User'

@description('The Resource ID of the user-assigned managed identity, in the form of /subscriptions/<subscriptionId>/resourceGroups/<ResourceGroupName>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<managedIdentity>.')
param managedIdentityResourceId string

@description('The firewall rules to configure access to the SQL server')
param firewallRules array = []

resource server 'Microsoft.Sql/servers@2021-05-01-preview' = {
  name: serverName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityResourceId}': {
      }
    }
  }
  properties: {
    primaryUserAssignedIdentityId: managedIdentityResourceId
    minimalTlsVersion: '1.2'
    administrators: {
      login: aadAdminName
      sid: aadAdminObjectId
      tenantId: aadAdminTenantId
      principalType: aadAdminType
      azureADOnlyAuthentication: true
    }
  }
}

@batchSize(1)
resource server_firewallRules 'Microsoft.Sql/servers/firewallRules@2020-02-02-preview' = [for rule in firewallRules: {
  name: rule.Name
  parent: server
  properties: {
    startIpAddress: rule.StartIpAddress
    endIpAddress: rule.EndIpAddress
  }
}]
