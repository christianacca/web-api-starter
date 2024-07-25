param settings object

targetScope = 'subscription'

// dev and prod container registries can be the same instance, therefore we use union to de-dup references to same registry
var containerRegistries = union(settings.ContainerRegistries.Available, [])

var sharedResourceGroups = map(containerRegistries, registry => registry.ResourceGroupName)

module resourceGroups 'br/public:avm/res/resources/resource-group:0.2.4' = [for (name, index) in sharedResourceGroups: {
  name: '${uniqueString(deployment().name)}-${index}-ResourceGroup'
  params: {
    name: name
  }
}]

module acrs 'br/public:avm/res/container-registry/registry:0.3.1' = [for (registry, index) in containerRegistries: {
  name: '${uniqueString(deployment().name)}-${index}-Acr'
  scope: resourceGroup((registry.SubscriptionId ?? subscription().subscriptionId), registry.ResourceGroupName)
  params: {
    name: registry.ResourceName
    acrSku: 'Basic'
  }
  dependsOn: [resourceGroups]
}]
