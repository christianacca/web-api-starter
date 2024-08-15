@description('The name of the Azure key vault whose RBAC role is to be assigned.')
param resourceName string

@description('The id of the principal to assign the RBAC role.')
param principalId string

@description('The role definition ID for the role assignment.')
param roleDefinitionId string

param location string = resourceGroup().location

resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: resourceName
}
module roleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: '${uniqueString(deployment().name, location)}-KeyVaultPermission'
  params: {
    principalId: principalId
    resourceId: kv.id
    roleDefinitionId: roleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
