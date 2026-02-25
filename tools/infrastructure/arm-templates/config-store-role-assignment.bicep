@description('The name of the Azure config store whose RBAC role is to be assigned.')
param resourceName string

@description('The id of the principal to assign the RBAC role.')
param principalId string

@description('The role definition ID for the role assignment.')
param roleDefinitionId string

param location string = resourceGroup().location

resource store 'Microsoft.AppConfiguration/configurationStores@2024-05-01' existing = {
  name: resourceName
}
module roleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: '${uniqueString(deployment().name, location)}-ConfigStorePermission'
  params: {
    principalId: principalId
    resourceId: store.id
    roleDefinitionId: roleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
