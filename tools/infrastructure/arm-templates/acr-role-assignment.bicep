@description('The name of the Azure container registry whose ACR Pull permission is to be assigned.')
param registryName string

@description('The id of the principal to assign the ACR Pull permission.')
param principalId string

@description('The role definition ID for the role assignment.')
param roleDefinitionId string

param location string = resourceGroup().location

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}
module acrPermission 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: '${uniqueString(deployment().name, location)}-AcrPermission'
  params: {
    principalId: principalId
    resourceId: acr.id
    roleDefinitionId: roleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
