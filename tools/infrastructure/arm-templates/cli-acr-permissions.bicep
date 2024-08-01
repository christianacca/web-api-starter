@description('The settings for all resources. TIP: to find the structure of settings object use: ./tools/infrastructure/get-product-conventions.ps1')
param settings object

targetScope = 'subscription'

// IMPORTANT: the permissions granted below assume that these service principal were created using the scripts from:
// https://github.com/MRI-Software/service-principal-automate
// and therefore have already been granted permissions to other resources they requires

// Note: assumes that the production registry is in the prod-na subscription. thus we are granting permissions to the 
// service principals that do NOT have permission to manage RBAC for resources in the prod-na subscription

var prodRegistry = settings.ContainerRegistries.Prod

var principalsIds = [
  '48dcc51c-d6f6-4152-9161-9f8c40e4cc1e' // cli-devops-shared-web-api-starter-arm
  '8ff2423c-e6ec-4643-8000-8063f624a8b9' // cli-apacdevopsproduction-prod-web-api-starter-arm
  '15be43a5-09a7-4c08-ac38-e1d16a27d7b1' // cli-emeadevopsproduction-prod-web-api-starter-arm
]

module acrRbacAssignmentPermissions 'acr-role-assignment.bicep' = [for (id, index) in principalsIds: {
  name: '${uniqueString(deployment().name)}-${index}-AcrRbacPermission'
  scope: resourceGroup((prodRegistry.SubscriptionId ?? subscription().subscriptionId), prodRegistry.ResourceGroupName)
  params: {
    principalId: id
    registryName: prodRegistry.ResourceName
    roleDefinitionId: 'f58310d9-a9f6-439a-9e8d-f62e7b41a168' // <- Role Based Access Control Administrator
  }
}]

// note: this is the least priviledge role in order to grant the Microsoft.Resources/deployments/write permission to the service principals
module acrTagContirbutorPermissions 'resource-group-role-assignment.bicep' = [for (id, index) in principalsIds: {
  name: '${uniqueString(deployment().name)}-${index}-TagsContrPermission'
  scope: resourceGroup((prodRegistry.SubscriptionId ?? subscription().subscriptionId), prodRegistry.ResourceGroupName)
  params: {
    principalId: id
    roleDefinitionId: '4a9ae827-6dc8-4573-8ac7-8239d42aa03f' // <- Tag Contributor
  }
}]
