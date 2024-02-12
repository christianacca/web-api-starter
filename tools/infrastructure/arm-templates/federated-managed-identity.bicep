@description('The name of the managed identity resource.')
param managedIdentityName string

@description('The Azure location where the managed identity should be created.')
param location string = resourceGroup().location

@description('The AKS cluster that this managed identity will federated tokens with.')
param aksCluster aksClusterType

@description('Optional. The failover AKS cluster that this managed identity will federated tokens with.')
param aksFailoverCluster aksClusterType?

@description('The name of the ServiceAccount k8 object that will be trusted to federate with AAD to acquire tokens.')
param aksServiceAccountName string

@description('The name of aks namespace that the ServiceAccount k8 object belongs to.')
param aksServiceAccountNamespace string

@description('List of RBAC role ids to grant to the managed identity scoped to the resource group of the managed identity.')
param rbacRoleIds array = []


resource aksPrimary 'Microsoft.ContainerService/managedClusters@2023-03-02-preview' existing = {
  name: aksCluster.resourceName
  // note: assumes that the managed identity for the api is in the same subscription as AKS
  scope: resourceGroup(aksCluster.resourceGroupName)
}

var fedCredantialPrimaryCluster = [
  {
    name: '${aksCluster.resourceName}-${aksServiceAccountName}'
    issuer: aksPrimary.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${aksServiceAccountNamespace}:${aksServiceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
]

resource aksFailover 'Microsoft.ContainerService/managedClusters@2023-03-02-preview' existing = if (!empty(aksFailoverCluster.?resourceName)) {
  name: aksFailoverCluster.?resourceName ?? 'dummy'
  // note: assumes that the managed identity for the api is in the same subscription as AKS
  scope: resourceGroup(aksFailoverCluster.?resourceGroupName ?? 'dummy')
}

var fedCredantialSecondaryCluster = !empty(aksFailoverCluster.?resourceName) ? [
  {
    name: '${aksFailoverCluster.?resourceName}-${aksServiceAccountName}'
    issuer: aksFailover.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${aksServiceAccountNamespace}:${aksServiceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
] : []

module managedIdentity 'managed-identity-with-rbac.bicep' = {
  name: '${uniqueString(deployment().name, location)}-FedManagedIdentity'
  params: {
    managedIdentityName: managedIdentityName
    location: location
    rbacRoleIds: rbacRoleIds
    federatedCredentials: concat(fedCredantialPrimaryCluster, fedCredantialSecondaryCluster)
  }
}

type aksClusterType = {
  @description('The name of AKS cluster that this managed identity will federated tokens with.')
  resourceName: string

  @description('The name of resource group containing the AKS cluster that this managed identity will federated tokens with.')
  resourceGroupName: string
}

@description('The resource ID of the user-assigned managed identity.')
output resourceId string = managedIdentity.outputs.resourceId

@description('The ID of the Azure AD application associated with the managed identity.')
output clientId string = managedIdentity.outputs.clientId
