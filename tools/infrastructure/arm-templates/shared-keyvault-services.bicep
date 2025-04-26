@description('List of shared Azure Key vaults storing TLS certificate used by product')
param tlsCertificateKeyVaults array

@description('The principal id of the Entra-ID security group that maintains the certificates')
param certMaintainerGroupId string

targetScope = 'subscription'

var uniqueKeyVaults = filter(
  // dev and prod key vaults can be the same instance, therefore we use union to de-dup
  union(tlsCertificateKeyVaults, []), 
  kv => empty(kv.SubscriptionId) || kv.SubscriptionId == subscription().subscriptionId
)

// dev and prod key vault resource groups can be same, therefore we use union to de-dup
var resourceGroupSettings = union(
  map(uniqueKeyVaults, kv => {
    ResourceGroupName: kv.ResourceGroupName
    ResourceLocation: kv.ResourceLocation
  }),
  []
)

var certMaintainerPrincipals = [
  {
    principalId: certMaintainerGroupId
    principalType: 'Group'
  }
]


module readerPermissions 'resource-group-role-assignment.bicep' = [for (rg, index) in resourceGroupSettings: {
  name: '${uniqueString(deployment().name)}-${index}-ReaderPermission'
  scope: resourceGroup(rg.ResourceGroupName)
  params: {
    principals: certMaintainerPrincipals
    roleDefinitionId: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // <- Reader
  }
}]

module keyVaults 'br/public:avm/res/key-vault/vault:0.11.0' = [for (kv, index) in uniqueKeyVaults: {
  name: '${uniqueString(deployment().name)}-${index}-KeyVault'
  scope: resourceGroup(kv.ResourceGroupName)
  params: {
    name: kv.ResourceName
    enablePurgeProtection: kv.EnablePurgeProtection
    location: kv.ResourceLocation
    sku: 'standard'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    roleAssignments: map(certMaintainerPrincipals, principal => {
      ...principal
      roleDefinitionIdOrName: 'Key Vault Certificates Officer'
    })
  }
}]
