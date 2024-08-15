@description('The id of the principal to assign the permission to.')
param principalId string

@description('The principal type of the assigned principal ID.')
@allowed([
  'Device'
  'ForeignGroup'
  'Group'
  'ServicePrincipal'
  'User'
])
param principalType string = 'ServicePrincipal'

@description('The role definition ID for the role assignment.')
param roleDefinitionId string

var qualifiedRoleDefinitionId = contains(roleDefinitionId, '/providers/Microsoft.Authorization/roleDefinitions/')
  ? roleDefinitionId
  : subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, qualifiedRoleDefinitionId)
  properties: {
    roleDefinitionId: qualifiedRoleDefinitionId
    principalId: principalId
    principalType: principalType
  }
}
