@description('The name of the managed identity resource.')
param managedIdentityName string

@description('The Azure location where the managed identity should be created.')
param location string = resourceGroup().location

@description('The name of AKS cluster that this managed identity will federated tokens with.')
param aksCluster string

@description('The name of resource group containing the AKS cluster that this managed identity will federated tokens with.')
param aksClusterResourceGroup string

@description('The name of the ServiceAccount k8 object that will be trusted to federate with AAD to acquire tokens.')
param aksServiceAccountName string

@description('The name of aks namespace that the ServiceAccount k8 object belongs to.')
param aksServiceAccountNamespace string

@description('The name of failover AKS cluster that this managed identity will federated tokens with.')
param aksFailoverCluster string = ''

@description('The name of resource group containing the failover AKS cluster that this managed identity will federated tokens with.')
param aksFailoverClusterResourceGroup string = ''


resource aksPrimary 'Microsoft.ContainerService/managedClusters@2023-03-02-preview' existing = {
  name: aksCluster
  // note: assumes that the managed identity for the api is in the same subscription as AKS
  scope: resourceGroup(aksClusterResourceGroup)
}

var fedCredantialPrimaryCluster = [
  {
    name: '${aksCluster}-${aksServiceAccountName}'
    issuer: aksPrimary.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${aksServiceAccountNamespace}:${aksServiceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
]

resource aksFailover 'Microsoft.ContainerService/managedClusters@2023-03-02-preview' existing = if (aksFailoverCluster != '') {
  name: aksFailoverCluster
  // note: assumes that the managed identity for the api is in the same subscription as AKS
  scope: resourceGroup(aksFailoverClusterResourceGroup)
}

var fedCredantialSecondaryCluster = aksFailoverCluster != '' ? [
  {
    name: '${aksCluster}-${aksServiceAccountName}'
    issuer: aksFailover.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${aksServiceAccountNamespace}:${aksServiceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
] : []

module managedIdentity 'managed-identity-with-rbac.bicep' = {
  name: '${managedIdentityName}Deployment'
  params: {
    managedIdentityName: managedIdentityName
    location: location
    rbacRoleIds: [
      '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
      'c6a89b2d-59bc-44d0-9896-0f6e12d7b80a' // Storage Queue Data Message Sender
    ]
    federatedCredentials: concat(fedCredantialPrimaryCluster, fedCredantialSecondaryCluster)
  }
}

@description('The resource ID of the user-assigned managed identity.')
output resourceId string = managedIdentity.outputs.resourceId
@description('The ID of the Azure AD application associated with the managed identity.')
output clientId string = managedIdentity.outputs.clientId
@description('The ID of the Azure AD service principal associated with the managed identity.')
output principalId string = managedIdentity.outputs.principalId
