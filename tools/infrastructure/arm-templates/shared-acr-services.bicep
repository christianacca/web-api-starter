@description('List of container registries setting objects that the product uses to push/pull docker images')
param containerRegistries array

targetScope = 'subscription'

var uniqueContainerRegistries = filter(
  // dev and prod container registries can be the same instance, therefore we use union to de-dup
  union(containerRegistries, []), 
  registry => empty(registry.SubscriptionId) || registry.SubscriptionId == subscription().subscriptionId
)

module acrs 'br/public:avm/res/container-registry/registry:0.6.0' = [for (registry, index) in uniqueContainerRegistries: {
  name: '${uniqueString(deployment().name)}-${index}-Acr'
  scope: resourceGroup(registry.ResourceGroupName)
  params: {
    name: registry.ResourceName
    acrSku: 'Basic'
  }
}]
