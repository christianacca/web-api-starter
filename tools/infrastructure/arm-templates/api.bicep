param acaEnvironmentResourceId string
param apiSettings object
param appInsightsConnectionString string
param exists bool
param primaryManagedIdentityClientId string
param subProductsSettings object
param userAssignedResourceIds array
param registries array

var location = resourceGroup().location

var initialAppImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
var appImage = exists ? existingApp.properties.template.containers[0].image : initialAppImage
// initial image does not define a http health endpoint at the path we want for our image, therefore for a reasonable
// default exerience when creating the container app for the first time fallback to defaults that container-apps will configure
var isInitialContainerImage = exists ? existingApp.properties.template.containers[0].image == initialAppImage : false

// the sample container exposes port 80, whereas our .net 8 app exposes 8080 which is the default for all .net apps now
var exposedContainerPort = isInitialContainerImage ? 80 : 8080

module appEnvVars 'desired-env-vars.bicep' = {
  name: '${uniqueString(deployment().name, location)}-AcaApiEnvVars'
  params: {
    envVars: [
      {
        name: 'Api__Database__UserID'
        value: primaryManagedIdentityClientId
      }
      {
        name: 'Api__Database__DataSource'
        value: subProductsSettings.Sql.Primary.DataSource
      }
      {
        name: 'Api__Database__InitialCatalog'
        value: subProductsSettings.Db.ResourceName
      }
      {
        name: 'Api__DefaultAzureCredentials__ManagedIdentityClientId'
        value: primaryManagedIdentityClientId
      }
      {
        name: 'Api__FunctionsAppQueue__ServiceUri'
        value: 'https://${subProductsSettings.InternalApi.StorageAccountName}.queue.${environment().suffixes.storage}'
      }
      {
        name: 'Api__FunctionsAppToken__Audience'
        value: subProductsSettings.InternalApi.AuthTokenAudience
      }
      {
        name: 'Api__KeyVaultName'
        value: subProductsSettings.KeyVault.ResourceName
      }
      {
        name: 'Api__ReverseProxy__Clusters__FunctionsApp__Destinations__Primary__Address'
        value: 'https://${subProductsSettings.InternalApi.HostName}'
      }
      {
        name: 'Api__ReportBlobStorage__ServiceUri'
        value: 'https://${subProductsSettings.PbiReportStorage.StorageAccountName}.blob.${environment().suffixes.storage}'
      }
      {
        name: 'ApplicationInsights__ConnectionString'
        value: appInsightsConnectionString
      }
    ]
    existingEnvVars: existingApp.properties.template.containers[0].?env ?? []
  }
}

module api 'br/public:avm/res/app/container-app:0.4.1' = {
  name: '${uniqueString(deployment().name, location)}-AcaApi'
  params: {
    containers: [
      {
        env: appEnvVars.outputs.desiredEnvVars
        image: appImage
        name: apiSettings.ResourceName
        probes: isInitialContainerImage ? [] : [
          { 
            type: 'Startup'
            initialDelaySeconds: 10
            httpGet: {
              port: exposedContainerPort
              path: '/health'
            }
          }
          { 
            type: 'Liveness'
            initialDelaySeconds: 3
            httpGet: {
              port: exposedContainerPort
              path: apiSettings.DefaultHealthPath
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
    environmentId: acaEnvironmentResourceId
    managedIdentities: {
      userAssignedResourceIds: userAssignedResourceIds
    }
    ingressAllowInsecure: false
    ingressTargetPort: exposedContainerPort
    name: apiSettings.ResourceName
    registries: registries
    scaleMaxReplicas: apiSettings.MaxReplicas
    scaleMinReplicas: apiSettings.MinReplicas
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

resource existingApp 'Microsoft.App/containerApps@2023-11-02-preview' existing = if (exists) {
  name: apiSettings.ResourceName
}
