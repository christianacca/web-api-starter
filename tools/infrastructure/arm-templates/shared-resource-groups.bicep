@description('The settings for all resources provisioned by this template. TIP: to find the structure of settings object use: ./tools/infrastructure/get-product-conventions.ps1')
param settings object

targetScope = 'subscription'

var configStores = settings.ConfigStores.IsDeployed ? [
  settings.ConfigStores.Dev
  settings.ConfigStores.Prod
] : []

var acrs = settings.ContainerRegistries.IsDeployed ? [
  settings.ContainerRegistries.Dev
  settings.ContainerRegistries.Prod
] : []

var keyVaults = settings.TlsCertificates.IsDeployed ? [
  settings.TlsCertificates.DevKeyVault
  settings.TlsCertificates.ProdKeyVault
] : []

var resources = filter(
  union(configStores, acrs, keyVaults),
  r => empty(r.SubscriptionId) || r.SubscriptionId == subscription().subscriptionId
)


// dev and prod store resource groups can be same, therefore we use union to de-dup
var uniqueResourceGroups = union(
  map(resources, r => {
    ResourceGroupName: r.ResourceGroupName
    ResourceLocation: r.ResourceLocation
  }),
  []
)

module resourceGroups 'br/public:avm/res/resources/resource-group:0.4.0' = [for rg in uniqueResourceGroups: {
  name: '${uniqueString(deployment().name)}-${rg.ResourceGroupName}-ResourceGroup'
  params: {
    name: rg.ResourceGroupName
    location: rg.ResourceLocation
  }
}]
