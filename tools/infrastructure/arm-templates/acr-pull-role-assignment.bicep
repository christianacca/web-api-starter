@description('The name of the Azure container registry whose ACR Pull permission is to be assigned.')
param registryName string

@description('The id of the principal to assign the ACR Pull permission.')
param principalId string

param location string = resourceGroup().location

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}
module acrPullPermission 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: '${uniqueString(deployment().name, location)}-AcrPullPermission'
  params: {
    principalId: principalId
    resourceId: acr.id
    roleDefinitionId: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // 'AcrPull'
    principalType: 'ServicePrincipal'
  }
}
