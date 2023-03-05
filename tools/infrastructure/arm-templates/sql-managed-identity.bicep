@description('The name of the managed identity resource.')
param managedIdentityName string

@description('The Azure location where the managed identity should be created.')
param location string = resourceGroup().location

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityName
  location: location
}

@description('The resource ID of the user-assigned managed identity.')
output resourceId string = managedIdentity.id
@description('The ID of the Azure AD application associated with the managed identity.')
output clientId string = managedIdentity.properties.clientId
@description('The ID of the Azure AD service principal associated with the managed identity.')
output principalId string = managedIdentity.properties.principalId