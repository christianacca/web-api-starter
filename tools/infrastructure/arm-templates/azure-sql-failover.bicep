@description('The name of the primary SQL Server.')
param sqlServerPrimaryName string

@description('The name of the secondary SQL Server.')
param sqlServerSecondaryName string

@description('The location of the secondary SQL Server.')
param sqlServerSecondaryRegion string

@description('The name of the failover group.')
param sqlFailoverGroupName string

@description('The name of the database.')
param databaseName string

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


module failoverServer './azure-sql-server.bicep' = {
  name: '${sqlServerSecondaryName}Deployment'
  params: {
    serverName: sqlServerSecondaryName
    location: sqlServerSecondaryRegion
    aadAdminName: aadAdminName
    aadAdminType: aadAdminType
    aadAdminObjectId: aadAdminObjectId
    aadAdminTenantId: aadAdminTenantId
    managedIdentityResourceId: managedIdentityResourceId
    firewallRules: firewallRules
  }
}

resource server_failoverGroup 'Microsoft.Sql/servers/failoverGroups@2021-05-01-preview' = {
  name: '${sqlServerPrimaryName}/${sqlFailoverGroupName}'
  properties: {
    partnerServers: [
      {
        id: resourceId('Microsoft.Sql/servers', sqlServerSecondaryName)
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
      resourceId('Microsoft.Sql/servers/databases', sqlServerPrimaryName, databaseName)
    ]
  }
  dependsOn: [
    failoverServer
  ]
}
