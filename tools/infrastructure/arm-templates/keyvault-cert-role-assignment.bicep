@description('The name of the Azure key vault storing the certficate.')
param keyVaultName string

@description('The name of the Azure key vault certificate whose RBAC role is to be assigned.')
param certificateName string

@description('The id of the principal to assign the RBAC role.')
param principalId string

@description('The role definition ID for the role assignment.')
param roleDefinitionId string

param location string = resourceGroup().location

resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
  resource cert 'secrets' existing = { name: certificateName }
}
module roleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: '${uniqueString(deployment().name, location)}-KeyVaultPermission'
  params: {
    principalId: principalId
    resourceId: kv::cert.id
    roleDefinitionId: roleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
