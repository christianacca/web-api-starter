import { acaSharedSettingsType } from 'utils.bicep'

param instanceSettings object
param exists bool
param sharedSettings acaSharedSettingsType

var location = instanceSettings.ResourceLocation

var initialAppImage = 'mcr.microsoft.com/dotnet/samples:aspnetapp'
var appImage = exists ? existingApp.properties.template.containers[0].image : initialAppImage
// initial image does not define a http health endpoint at the path we want for our image, therefore for a reasonable
// default exerience when creating the container app for the first time fallback to defaults that container-apps will configure
var isInitialContainerImage = exists ? existingApp.properties.template.containers[0].image == initialAppImage : true

// 8080 which is the default for all .net 8 apps now
var exposedContainerPort = 8080

module appEnvVars 'desired-env-vars.bicep' = {
  name: '${uniqueString(deployment().name, location)}-AcaEnvVars'
  params: {
    envVars: [
      {
        name: 'App__ConfigStoreReplicaDiscoveryEnabled'
        value: length(sharedSettings.configStoreSettings.ReplicaLocations) > 0 ? 'true' : 'false'
      }
      {
        name: 'App__ConfigStoreUri'
        value: 'https://${sharedSettings.configStoreSettings.HostName}'
      }
      {
        name: 'App__Database__DataSource'
        value: sharedSettings.subProductsSettings.Sql.Primary.DataSource
      }
      {
        name: 'App__Database__InitialCatalog'
        value: sharedSettings.subProductsSettings.Db.ResourceName
      }
      {
        name: 'App__Database__UserID'
        value: sharedSettings.managedIdentities.default.clientId
      }
      {
        name: 'App__DefaultAzureCredentials__ManagedIdentityClientId'
        value: sharedSettings.managedIdentities.default.clientId
      }
      {
        name: 'App__KeyVaultName'
        value: sharedSettings.subProductsSettings.KeyVault.ResourceName
      }
      {
        name: 'ApplicationInsights__ConnectionString'
        value: sharedSettings.appInsightsConnectionString
      }
    ]
    existingEnvVars: exists ? existingApp.properties.template.containers[0].?env ?? [] : []
  }
}

module app 'br/public:avm/res/app/container-app:0.11.0' = {
  name: '${uniqueString(deployment().name, location)}-Aca'
  params: {
    containers: [
      {
        env: appEnvVars.outputs.desiredEnvVars
        image: appImage
        name: instanceSettings.ResourceName
        probes: isInitialContainerImage ? [] : [
          { 
            type: 'Startup'
            initialDelaySeconds: 10
            httpGet: {
              port: exposedContainerPort
              path: instanceSettings.DefaultHealthPath
            }
          }
          { 
            type: 'Liveness'
            initialDelaySeconds: 3
            httpGet: {
              port: exposedContainerPort
              path: instanceSettings.DefaultHealthPath
            }
          }
        ]
        resources: {
          // IMPORTANT: if you change these values you will need to recalculate scaleRules below which depend on these resource values
          cpu: json('0.25')
          memory: '0.5Gi'
        }
      }
    ]
    customDomains: sharedSettings.isCustomDomainEnabled ? [
      {
        name: sharedSettings.subProductsSettings.App.HostName
        certificateId: acaEnv::cert.id
        bindingType: 'SniEnabled'
      }
    ] : []
    environmentResourceId: acaEnv.id
    managedIdentities: {
      userAssignedResourceIds: union(
        [sharedSettings.managedIdentities.default.resourceId],
        map(sharedSettings.managedIdentities.?others ?? [], identity => identity.resourceId)
      )
    }
    ingressAllowInsecure: false
    ingressTargetPort: exposedContainerPort
    name: instanceSettings.ResourceName
    location: location
    registries: sharedSettings.registries
    scaleMaxReplicas: instanceSettings.MaxReplicas
    scaleMinReplicas: instanceSettings.MinReplicas
    scaleRules : [{
      http: {
        metadata: {
          // this number is a function of resources allocated above. the value selected was based on the following assumptions:
          // - async/await is utilized so as to improve thread handling efficiency
          // - asp.net core running a typical CRUD workload with an Azure SQL database as it's persistent store that's located
          //   in the same azure region as the container app
          // - each request to the api will result in typically 5-10 requests to the Azure SQL database
          // - some of the requests to the api will also result in dependent request to power bi REST api
          // - each dependent database and REST api request is likely to return between 5K-20K bytes of data
          // IMPORTANT: this value was calculated by chatgbt using the following prompt: https://chatgpt.com/share/37b6ef34-bf0b-4e7b-8e51-99373c1579b7
          concurrentRequests : '10'
        }
      }
      name: 'http-scaling'
    }]
    workloadProfileName: 'Consumption'
  }
}

resource acaEnv 'Microsoft.App/managedEnvironments@2023-11-02-preview' existing = {
  name: instanceSettings.AcaEnvResourceName
  resource cert 'certificates' existing = if (sharedSettings.isCustomDomainEnabled) { name: sharedSettings.certSettings.ResourceName }
}

resource existingApp 'Microsoft.App/containerApps@2023-11-02-preview' existing = if (exists) {
  name: instanceSettings.ResourceName
}