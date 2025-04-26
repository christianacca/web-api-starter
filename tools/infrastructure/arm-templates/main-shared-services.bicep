@description('The principal id of the Entra-ID security group that maintains TLS certificates')
param certMaintainerGroupId string

@description('The principal/object id of the service principal that is used to deploy this product to dev/test environments. This is required when `grantRbacManagement` parameter is true')
param devServicePrincipalId string?

@description('Whether to assign RBAC permissions to the service principals that are used to deploy this product. Setting this to true will require `devServicePrincipalId` and `otherProdServicePrincipalIds` to be supplied')
param grantRbacManagement bool = false

@description('The principal/object id of the service principal that is used to deploy this product to the non-default production environment. Will only be used if `grantRbacManagement` parameter is true')
param otherProdServicePrincipalIds array = []

@description('The settings for all resources provisioned by this template. TIP: to find the structure of settings object use: ./tools/infrastructure/get-product-conventions.ps1')
param settings object

targetScope = 'subscription'

var subscriptionId = subscription().id

module resourceGroups 'shared-resource-groups.bicep' = {
  name: '${uniqueString(deployment().name, subscriptionId)}-ResourceGroup'
  params: {
    settings: settings
  }
}

module containerRegistries 'shared-acr-services.bicep' = if (settings.ContainerRegistries.IsDeployed) {
  name: '${uniqueString(deployment().name, subscriptionId)}-SharedContainerRegistry'
  params: {
    containerRegistries: [
      settings.ContainerRegistries.Dev
      settings.ContainerRegistries.Prod
    ]
  }
  dependsOn: [resourceGroups]
}

module tlsCertKeyVaults 'shared-keyvault-services.bicep' = if (settings.TlsCertificates.IsDeployed) {
  name: '${uniqueString(deployment().name, subscriptionId)}-SharedKeyVault'
  params: {
    certMaintainerGroupId: certMaintainerGroupId
    tlsCertificateKeyVaults: [
      settings.TlsCertificates.Dev.KeyVault
      settings.TlsCertificates.Prod.KeyVault
    ]
  }
  dependsOn: [resourceGroups]
}

module configStores 'shared-config-store-services.bicep' = if (settings.ConfigStores.IsDeployed) {
  name: '${uniqueString(deployment().name, subscriptionId)}-SharedConfigStore'
  params: {
    configStores: [
      settings.ConfigStores.Dev
      settings.ConfigStores.Prod
    ]
  }
  dependsOn: [resourceGroups]
}

module cliPermissions 'cli-permissions.bicep' = if (grantRbacManagement) {
  name: '${uniqueString(deployment().name, subscriptionId)}-CliPermission'
  params: {
    settings: settings
    devServicePrincipalId: devServicePrincipalId!
    otherProdServicePrincipalIds: otherProdServicePrincipalIds
  }
  dependsOn: [containerRegistries, tlsCertKeyVaults, configStores]
}