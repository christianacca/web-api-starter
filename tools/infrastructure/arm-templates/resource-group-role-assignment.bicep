@description('The role definition ID for the role assignment.')
param roleDefinitionId string

@description('List of principals to assign to the role')
param principals principalsType

var qualifiedRoleDefinitionId = contains(roleDefinitionId, '/providers/Microsoft.Authorization/roleDefinitions/')
  ? roleDefinitionId
  : subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (principal, index) in principals: {
  name: guid(resourceGroup().id, principal.principalId, qualifiedRoleDefinitionId)
  properties: {
    roleDefinitionId: qualifiedRoleDefinitionId
    ...principal
  }
}]

// =============== //
//   Definitions   //
// =============== //


type princialObjectType = {
  principalId: string
  principalType: 'Device' | 'ForeignGroup' | 'Group' | 'ServicePrincipal' | 'User'
}

type principalsType = princialObjectType[]
