@description('Storage Account type')
@allowed([
  'Premium_LRS'
  'Premium_ZRS'
  'Standard_GRS'
  'Standard_GZRS'
  'Standard_LRS'
  'Standard_RAGRS'
  'Standard_RAGZRS'
  'Standard_ZRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Location for the storage account.')
param location string = resourceGroup().location

@description('The name of the Storage Account')
param storageAccountName string = 'store${uniqueString(resourceGroup().id)}'

@description('The default access tier used for blob storage. Hot for frequently accessed data or Cool for infrequently accessed data')
@allowed([
  'Hot'
  'Cool'
])
param defaultStorageTier string = 'Hot'

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    accessTier: defaultStorageTier
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    defaultToOAuthAuthentication: true
  }
}

resource storageAccountName_default 'Microsoft.Storage/storageAccounts/blobServices@2021-09-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      retentionInDays: 95
      enabled: true
    }
    restorePolicy: {
      enabled: true
      days: 90
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 90
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 95
    }
    isVersioningEnabled: true
  }
}

resource Microsoft_Storage_storageAccounts_managementPolicies_storageAccountName_default 'Microsoft.Storage/storageAccounts/managementPolicies@2021-02-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          definition: {
            actions: {
              version: {
                delete: {
                  daysAfterCreationGreaterThan: 90
                }
              }
            }
            filters: {
              blobTypes: [
                'blockBlob'
              ]
            }
          }
          enabled: true
          name: 'retention-lifecyle'
          type: 'Lifecycle'
        }
      ]
    }
  }
}

output storageAccountName string = storageAccountName
output storageAccountId string = storageAccount.id
