@description('List of container registries setting objects that the product uses to push/pull docker images')
param containerRegistries array

targetScope = 'subscription'

var uniqueContainerRegistries = filter(
  // dev and prod container registries can be the same instance, therefore we use union to de-dup
  union(containerRegistries, []), 
  registry => empty(registry.SubscriptionId) || registry.SubscriptionId == subscription().subscriptionId
)

// dev and prod registry resource groups can be same, therefore we use union to de-dup
var resourceGroupNames = union(map(uniqueContainerRegistries, registry => registry.ResourceGroupName), [])

module resourceGroups 'br/public:avm/res/resources/resource-group:0.2.4' = [for (name, index) in resourceGroupNames: {
  name: '${uniqueString(deployment().name)}-${index}-ResourceGroup'
  params: {
    name: name
  }
}]

module acrs 'br/public:avm/res/container-registry/registry:0.3.1' = [for (registry, index) in uniqueContainerRegistries: {
  name: '${uniqueString(deployment().name)}-${index}-Acr'
  scope: resourceGroup(registry.ResourceGroupName)
  params: {
    name: registry.ResourceName
    acrSku: 'Basic'
  }
  dependsOn: [resourceGroups]
}]
