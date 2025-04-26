@description('List of shared Azure Configuration Stores used by the product')
param configStores array

targetScope = 'subscription'

var uniqueConfigStores = filter(
  // dev and prod store can be the same instance, therefore we use union to de-dup
  union(configStores, []), 
  store => empty(store.SubscriptionId) || store.SubscriptionId == subscription().subscriptionId
)

module stores 'br/public:avm/res/app-configuration/configuration-store:0.6.3' = [for (store, index) in uniqueConfigStores: {
  name: '${uniqueString(deployment().name)}-${index}-ConfigStore'
  scope: resourceGroup(store.ResourceGroupName)
  params: {
    name: store.ResourceName
    enablePurgeProtection: store.EnablePurgeProtection
    location: store.ResourceLocation
    replicaLocations: store.ReplicaLocations
  }
}]
