import { acaSharedSettingsType } from 'utils.bicep'

param instanceSettings object
param exists bool
param sharedSettings acaSharedSettingsType

var location = instanceSettings.ResourceLocation

var initialAppImage = 'mcr.microsoft.com/dotnet/samples:aspnetapp'
var appImage = existingApp.?properties.template.containers[0].image ?? initialAppImage
// initial image does not define a http health endpoint at the path we want for our image, therefore for a reasonable
// default exerience when creating the container app for the first time fallback to defaults that container-apps will configure
var isInitialContainerImage = (existingApp.?properties.template.containers[0].image ?? initialAppImage) == initialAppImage

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
    existingEnvVars: exists ? existingApp.?properties.template.containers[0].?env ?? [] : []
  }
}

module app 'br/public:avm/res/app/container-app:0.20.0' = {
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
    scaleSettings: {
      maxReplicas: instanceSettings.MaxReplicas
      minReplicas: instanceSettings.MinReplicas
      rules: [
        {
          http: {
            metadata: {
              // The base memory-safe concurrency limit for this container is 10 concurrent requests, derived from:
              // - async/await utilized for thread handling efficiency
              // - ASP.NET Core frontend app proxying requests to the API layer
              // - each page/request may result in multiple downstream API calls and asset fetches
              // - 0.5Gi memory allocated; at 10 concurrent requests the container approaches memory saturation
              // See original calculation: https://chatgpt.com/share/37b6ef34-bf0b-4e7b-8e51-99373c1579b7
              //
              // The threshold is raised from 10 to 25 to prevent health monitoring traffic from causing
              // spurious scale-out. Infrastructure health monitoring generates the following background requests:
              // - Traffic Manager health probe: 1 probe every 30 seconds (standard Azure TM probe interval)
              // - Azure Monitor availability tests: 5 geographic locations (default location set), each probing
              //   every 15 minutes (configured via Get-ResourceConvention.ps1 AvailabilityTest Frequency),
              //   which can arrive in near-simultaneous bursts of up to 5 concurrent requests
              // Maximum concurrent health monitoring requests: ~6 (1 TM + 5 availability test locations)
              // The threshold of 25 provides a comfortable margin above this maximum.
              //
              // IMPORTANT: raising the http threshold above the memory-safe limit of 10 is only safe because
              // the 'memory-scaling' rule below acts as a backstop, triggering scale-out before the container
              // reaches memory saturation when 11-24 concurrent real requests are in-flight.
              concurrentRequests: '25'
            }
          }
          name: 'http-scaling'
        }
        {
          custom: {
            // Backstop rule that triggers scale-out when the container approaches memory saturation.
            // This guards the gap between the http rule threshold (25 concurrent) and the memory-safe
            // concurrency limit (10 concurrent): if 11-24 heavy or slow requests are in-flight simultaneously,
            // the container can approach OOM before the http rule fires.
            // 80% of 0.5Gi = ~410MB; idle memory baseline is ~61.5% (~307MB), giving ~103MB headroom.
            // NOTE: this rule polls every ~30s - it is a lagging safety net, not a first-line scale trigger.
            metadata: {
              type: 'Utilization'
              value: '80'
            }
            type: 'memory'
          }
          name: 'memory-scaling'
        }
      ]
    }
    workloadProfileName: 'Consumption'
  }
}

resource acaEnv 'Microsoft.App/managedEnvironments@2025-10-02-preview' existing = {
  name: instanceSettings.AcaEnvResourceName
  resource cert 'certificates' existing = if (sharedSettings.isCustomDomainEnabled) { name: sharedSettings.certSettings.ResourceName }
}

resource existingApp 'Microsoft.App/containerApps@2025-10-02-preview' existing = if (exists) {
  name: instanceSettings.ResourceName
}
