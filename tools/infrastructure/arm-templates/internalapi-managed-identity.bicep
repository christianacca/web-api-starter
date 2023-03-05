@description('The name of the managed identity resource.')
param managedIdentityName string

@description('The Azure location where the managed identity should be created.')
param location string = resourceGroup().location

module managedIdentity 'managed-identity-with-rbac.bicep' = {
  name: '${managedIdentityName}Deployment'
  params: {
    managedIdentityName: managedIdentityName
    location: location
    rbacRoleIds: [
      '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
      '8a0f0c08-91a1-4084-bc3d-661d67233fed' // Storage Queue Data Message Processor
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    ]
  }
}

@description('The resource ID of the user-assigned managed identity.')
output resourceId string = managedIdentity.outputs.resourceId
@description('The ID of the Azure AD application associated with the managed identity.')
output clientId string = managedIdentity.outputs.clientId
@description('The ID of the Azure AD service principal associated with the managed identity.')
output principalId string = managedIdentity.outputs.principalId
