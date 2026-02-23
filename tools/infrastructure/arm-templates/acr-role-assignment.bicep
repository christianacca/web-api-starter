@description('The name of the Azure container registry whose RBAC role is to be assigned.')
param resourceName string

@description('The id of the principal to assign the RBAC role.')
param principalId string

@description('The role definition ID for the role assignment.')
param roleDefinitionId string

param location string = resourceGroup().location

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: resourceName
}
module acrPermission 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: '${uniqueString(deployment().name, location)}-AcrPermission'
  params: {
    principalId: principalId
    resourceId: acr.id
    roleDefinitionId: roleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
