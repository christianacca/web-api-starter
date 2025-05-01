
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
func toManagedIdentityInfo(obj object) managedIdentityInfoType => ({
  resourceId: obj.resourceId
  clientId: obj.properties.clientId
})

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
  isCustomDomainEnabled: bool
  managedIdentities: acaManagedIdentitiesType
  subProductsSettings: object
  registries: array
}