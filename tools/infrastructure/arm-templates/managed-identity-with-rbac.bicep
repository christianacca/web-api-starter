@description('The name of the managed identity resource.')
param managedIdentityName string

@description('The Azure location where the managed identity should be created.')
param location string = resourceGroup().location

@description('List of RBAC role ids to grant to the managed identity scoped to the resource group of the managed identity.')
param rbacRoleIds array = []

var rbacRoleResourceIds = map(rbacRoleIds, (id) => subscriptionResourceId('Microsoft.Authorization/roleDefinitions', id))

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityName
  location: location
}

resource rbacAssignments 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = [for resourceId in rbacRoleResourceIds: {
  name: guid(managedIdentity.id, resourceGroup().id, resourceId)
  properties: {
    #disable-next-line use-resource-id-functions
    roleDefinitionId: resourceId
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

@description('The resource ID of the user-assigned managed identity.')
output resourceId string = managedIdentity.id
@description('The ID of the Azure AD application associated with the managed identity.')
output clientId string = managedIdentity.properties.clientId
@description('The ID of the Azure AD service principal associated with the managed identity.')
output principalId string = managedIdentity.properties.principalId
