@description('The principal/object id of the service principal that is used to deploy this product to the apac environment')
param apacProdServicePrincipalId string

@description('The principal/object id of the service principal that is used to deploy this product to dev/test environments')
param devServicePrincipalId string

@description('The principal/object id of the service principal that is used to deploy this product to the emea environment')
param emeaProdServicePrincipalId string

@description('The settings for all resources. TIP: to find the structure of settings object use: ./tools/infrastructure/get-product-conventions.ps1')
param settings object

targetScope = 'subscription'

// IMPORTANT: the permissions granted below assume that these service principal were created using the scripts from:
// https://github.com/MRI-Software/service-principal-automate
// and therefore have already been granted permissions to create/update resources in their "home" subscription.

// Note: assumes that the production registry and shared key vault are in the prod-na subscription. thus we are granting
// permissions to the service principals that do NOT have permission to manage RBAC for resources in the prod-na subscription

var prodRegistry = settings.ContainerRegistries.Prod

// union used to de-dup id's supplied
var principalsIdsAcrAccess = union([
  devServicePrincipalId
  apacProdServicePrincipalId
  emeaProdServicePrincipalId
], [])

module acrRbacAssignmentPermissions 'acr-role-assignment.bicep' = [for (id, index) in principalsIdsAcrAccess: {
  name: '${uniqueString(deployment().name)}-${index}-AcrRbacPermission'
  scope: resourceGroup((prodRegistry.SubscriptionId ?? subscription().subscriptionId), prodRegistry.ResourceGroupName)
  params: {
    principalId: id
    resourceName: prodRegistry.ResourceName
    roleDefinitionId: 'f58310d9-a9f6-439a-9e8d-f62e7b41a168' // <- Role Based Access Control Administrator
  }
}]

var prodTlsCertKeyVault = settings.TlsCertificates.Prod.KeyVault
var devTlsCertKeyVault = settings.TlsCertificates.Dev.KeyVault

var uniqueKeyVaults = union([prodTlsCertKeyVault, devTlsCertKeyVault], [])
var isSingleSharedVault = length(uniqueKeyVaults) == 1

var principalsIdsKeyVaultAccess = union([
    apacProdServicePrincipalId
    emeaProdServicePrincipalId
  ],
  isSingleSharedVault ? [devServicePrincipalId] : []
)

module keyVaultRbacAssignmentPermissions 'keyvault-role-assignment.bicep' = [for (id, index) in principalsIdsKeyVaultAccess: {
  name: '${uniqueString(deployment().name)}-${index}-AcrRbacPermission'
  scope: resourceGroup((prodTlsCertKeyVault.SubscriptionId ?? subscription().subscriptionId), prodTlsCertKeyVault.ResourceGroupName)
  params: {
    principalId: id
    resourceName: devTlsCertKeyVault.ResourceName
    roleDefinitionId: '8b54135c-b56d-4d72-a534-26097cfdc8d8' // <- Key Vault Data Access Administrator
  }
}]

var resourceGroupDeployments = union(
  map(principalsIdsAcrAccess, principalId => ({
    principalId: principalId
    resourceGroupName: prodRegistry.ResourceGroupName
    resourceGroupSubscriptionId: prodRegistry.SubscriptionId
  })),
  map(principalsIdsKeyVaultAccess, principalId => ({
    principalId: principalId
    resourceGroupName: prodTlsCertKeyVault.ResourceGroupName
    resourceGroupSubscriptionId: prodTlsCertKeyVault.SubscriptionId
  }))
)


// note: this is the least priviledge role in order to grant the Microsoft.Resources/deployments/write permission to the service principals
// doing so is required so as to be able to execute the bicep deployment template targeting resources in the resource group
module tagContirbutorPermissions 'resource-group-role-assignment.bicep' = [for (x, index) in resourceGroupDeployments: {
  name: '${uniqueString(deployment().name)}-${index}-TagsContrPermission'
  scope: resourceGroup((x.resourceGroupSubscriptionId ?? subscription().subscriptionId), x.resourceGroupName)
  params: {
    principalId: x.principalId
    roleDefinitionId: '4a9ae827-6dc8-4573-8ac7-8239d42aa03f' // <- Tag Contributor
  }
}]
