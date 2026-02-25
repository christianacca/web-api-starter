
@export()
func findFirstBy(list array, key string, value string) object? => first(filter(list, x => x[key] == value))

@export()
func unionBy(firstArray array, secondArray array, key string) array => [
  ...firstArray
  ...filter(secondArray, item => findFirstBy(firstArray, key, item[key]) == null)
]

@export()
func objectValues(obj object) array => map(items(obj), x => x.value)

@export()
type managedIdentityInfoType = {
  @description('Required. The resource id of the managed identity.')
  resourceId: string
  @description('Required. The client/app id of the managed identity.')
  clientId: string
}

@export()
type acaManagedIdentitiesType = {
  @description('Required. The the managed identity used as the default/primary identity for the container app.')
  default: managedIdentityInfoType
  others: managedIdentityInfoType[]?
}

@export()
type acaSharedSettingsType = {
  appInsightsConnectionString: string
  certSettings: object
  configStoreSettings: object
  isCustomDomainEnabled: bool
  managedIdentities: acaManagedIdentitiesType
  subProductsSettings: object
  registries: resourceInput<'Microsoft.App/containerApps@2025-10-02-preview'>.properties.configuration.registries
}

@export()
@description('Settings for a shared Azure Container Registry used by the product.')
type containerRegistrySettingsType = {
  @description('Optional. The subscription ID where the registry resides. Defaults to current subscription if empty.')
  SubscriptionId: string?
  ResourceGroupName: string
  @description('Required. The resource name of the registry.')
  ResourceName: string
}

@export()
@description('Settings for a shared Azure App Configuration Store used by the product.')
type configStoreSettingsType = {
  @description('Optional. The subscription ID where the store resides. Defaults to current subscription if empty.')
  SubscriptionId: string?
  ResourceGroupName: string
  @description('Required. The resource name of the store.')
  ResourceName: string
  @description('Required. Whether to enable purge protection.')
  EnablePurgeProtection: bool
  @description('Required. The location of the store.')
  ResourceLocation: string
  @description('Required. The replica locations for the store.')
  ReplicaLocations: string[]
}

@export()
@description('Settings for a shared Azure Key Vault storing TLS certificates used by the product.')
type tlsCertKeyVaultSettingsType = {
  @description('Optional. The subscription ID where the key vault resides. Defaults to current subscription if empty.')
  SubscriptionId: string?
  ResourceGroupName: string
  @description('Required. The resource name of the key vault.')
  ResourceName: string
  @description('Required. Whether to enable purge protection.')
  EnablePurgeProtection: bool
  @description('Required. The location of the key vault.')
  ResourceLocation: string
}
