param settings object

targetScope = 'subscription'

var keyVaultSettings = filter(
  // dev and prod key vaults can be the same instance, therefore we use union to de-dup
  union([settings.TlsCertificates.Dev.KeyVault, settings.TlsCertificates.Prod.KeyVault], []), 
  kv => empty(kv.SubscriptionId) || kv.SubscriptionId == subscription().subscriptionId
)

// dev and prod key vault resource groups can be same, therefore we use union to de-dup
var resourceGroupNames = union(map(keyVaultSettings, kv => kv.ResourceGroupName), [])

// set this variable to the object id of a security group whose members are responsible for maintaining certifcates for this product 
var certMaintainerGroupId = '62a97169-c40e-4234-9b32-2d8eb9fb600e' // <- sg.role.it.itops.cloud.standard
// var certMaintainerGroupId = '7940cd4d-88fc-453c-8c76-9717ae986e60' // <- sg.role.it.itops.cloud.standard

module resourceGroups 'br/public:avm/res/resources/resource-group:0.2.4' = [for (name, index) in resourceGroupNames: {
  name: '${uniqueString(deployment().name)}-${index}-ResourceGroup'
  params: {
    name: name
  }
}]


module readerPermissions 'resource-group-role-assignment.bicep' = [for (name, index) in resourceGroupNames: if(!empty(certMaintainerGroupId)) {
  name: '${uniqueString(deployment().name)}-${index}-ReaderPermission'
  scope: resourceGroup(name)
  params: {
    principalId: certMaintainerGroupId
    principalType: 'Group'
    roleDefinitionId: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // <- Reader
  }
  dependsOn: [resourceGroups]
}]

module keyVaults 'br/public:avm/res/key-vault/vault:0.6.2' = [for (kv, index) in keyVaultSettings: {
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
    roleAssignments: !empty(certMaintainerGroupId) ? [
      { principalId: certMaintainerGroupId, roleDefinitionIdOrName: 'Key Vault Certificates Officer', principalType: 'Group' }
    ] : []
  }
  dependsOn: [resourceGroups]
}]
