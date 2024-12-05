@description('List of shared Azure Key vaults storing TLS certificate used by product')
param tlsCertificateKeyVaults array

@description('The principal id of the Entra-ID security group that maintains the certificates')
param certMaintainerGroupId string

targetScope = 'subscription'

var keyVaultSettings = filter(
  // dev and prod key vaults can be the same instance, therefore we use union to de-dup
  union(tlsCertificateKeyVaults, []), 
  kv => empty(kv.SubscriptionId) || kv.SubscriptionId == subscription().subscriptionId
)

// dev and prod key vault resource groups can be same, therefore we use union to de-dup
var resourceGroupNames = union(map(keyVaultSettings, kv => kv.ResourceGroupName), [])

var certMaintainerPrincipals = [
  {
    principalId: certMaintainerGroupId
    principalType: 'Group'
  }
]

module resourceGroups 'br/public:avm/res/resources/resource-group:0.4.0' = [for (name, index) in resourceGroupNames: {
  name: '${uniqueString(deployment().name)}-${index}-ResourceGroup'
  params: {
    name: name
  }
}]


module readerPermissions 'resource-group-role-assignment.bicep' = [for (name, index) in resourceGroupNames: {
  name: '${uniqueString(deployment().name)}-${index}-ReaderPermission'
  scope: resourceGroup(name)
  params: {
    principals: certMaintainerPrincipals
    roleDefinitionId: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // <- Reader
  }
  dependsOn: [resourceGroups]
}]

module keyVaults 'br/public:avm/res/key-vault/vault:0.11.0' = [for (kv, index) in keyVaultSettings: {
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
  dependsOn: [resourceGroups]
}]
