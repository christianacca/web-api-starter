<!-- TOC -->
* [Instructions for adding a new application to the solution](#instructions-for-adding-a-new-application-to-the-solution)
  * [1. Create a new dotnet project and add to solution](#1-create-a-new-dotnet-project-and-add-to-solution)
  * [2. Add docker support](#2-add-docker-support)
  * [3. Extend infra-as-code conventions for new app](#3-extend-infra-as-code-conventions-for-new-app)
  * [4. Add initial azure container app definition to infra-as-code bicep](#4-add-initial-azure-container-app-definition-to-infra-as-code-bicep)
  * [5. Adjust infra-as-code provisioning scripts](#5-adjust-infra-as-code-provisioning-scripts)
  * [6. Adjust dev deploy script to deploy new azure container app](#6-adjust-dev-deploy-script-to-deploy-new-azure-container-app)
  * [7. Update dev setup guide](#7-update-dev-setup-guide)
  * [8. Update add environment guide](#8-update-add-environment-guide)
  * [9. Add app to the solution's CI/CD pipeline](#9-add-app-to-the-solutions-cicd-pipeline)
  * [10. Implement custom domain for the new app](#10-implement-custom-domain-for-the-new-app)
<!-- TOC -->

# Instructions for adding a new application to the solution

> [!IMPORTANT]
> For the purposes of this guide, the name of the MVC web application will be Template.App. For your app, pick a name that
> is suitable for your solution. Use that name and substitute `Template.App`, `App` and `app` in the instructions below.
> For example, if you chose `Template.Web` then use the following substitutions: `Template.Web`, `Web` and `web`.

## 1. Create a new dotnet project and add to solution

1. Create project

   EG:

   ```bash
   dotnet new mvc -o src/Template.App
   dotnet sln add ./src/Template.Web/Template.App.csproj --in-root
   ```
   
2. Modify the csproj file to preferred conventions

   Replace the content of the initial csproj file with the following:

   ```xml
   <Project Sdk="Microsoft.NET.Sdk.Web">
   
     <PropertyGroup>
       <TargetFramework>net10.0</TargetFramework>
     </PropertyGroup>
   
   </Project>
   ```

3. Modify launchSettings.json to remove IIS Epress settings

    * Open src/Template.App/Properties/launchSettings.json
    * Remove the following JSON elements:
        * `iisSettings`
        * `profiles/http`
        * `profiles/IIS Express`
    * Rename `profiles/https` to `Template.App` and adjust as follows:
        * change `applicationUrl` setting to remove the http url and optionally modify the port to 5001
   
4. Add basic health probe to the app
   * This is **critical setup** as later the azure container app will use this to determine if the app is healthy
   * Follow guidance [here](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks#basic-health-probe), except:
     * Use the path `/health` instead of `/healthcheck`

5. Verify app creation

   * Run the app

     ```bash
     dotnet run --project ./src/Template.App
     ```

   * Check that the basics are running:
     * browsing to home page: <https://localhost:5001>
     * browsing to health: <https://localhost:5001/health>

6. Add user secrets

   ```pwsh
   dotnet user-secrets init -p src/Template.App/Template.App.csproj
   ```
   
7. Add initial appsettings section for settings specific to the new app

   * Add the following to the appsettings.Development.json file
    
     ```json
     {
        "App": {
          "ConnectionStrings": {
            "AppDatabase": "Data Source=(localdb)\\MSSQLLocalDB;Initial Catalog=web-api-starter;Integrated Security=True;TrustServerCertificate=true;"
          }
        }
     }
     ```
     
     Name the section to match the new app name. For example if your app was named `Template.Web`, then
     the section name would be `Web`.

## 2. Add docker support

[!NOTE]
We are NOT going to add the dotnet / visual studio tooling support for docker. This is because we are not using docker 
for "inner-loop" development.

1. Add Dockerfile file 

   add file named Dockerfile to the root of the new project with the following definition:

   ```yaml
   FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled-extra
   #EXPOSE 8080 <- this is the default port that a .net application will be configured to listen on and is the port exposed in the base docker image
   
   WORKDIR /app
   
   ENTRYPOINT ["dotnet", "Template.App.dll"] # <- this needs to match the name of the project
   COPY . .
   ```

2. Add .dockerignore file

   add file named .dockerignore to the root of the new project with the following definition:

   ```plaintext
   Dockerfile
   ```

3. Modify the csproj file to ensure docker file is copied to the output

   Add `IsPublishable` property to the csproj file. EG:

   ```xml
   <!-- SNIP -->
   <PropertyGroup>
     <TargetFramework>net10.0</TargetFramework>
     <IsPublishable>true</IsPublishable>
   </PropertyGroup>
   ```

## 3. Extend infra-as-code conventions for new app

1. Add app created above to [get-product-conventions.ps1](../tools/infrastructure/get-product-conventions.ps1)

   EG:

   ```pwsh
   App                 = @{
       AdditionalManagedId = 'AcrPull'
       Type = 'AcaApp'
   }
   AppAvailabilityTest =   @{ Type = 'AvailabilityTest'; Target = 'App' }
   AppTrafficManager   =   @{ Type = 'TrafficManager'; Target = 'App' }
   ```

   To see the new app conventions:

   ```pwsh
   $dev = ./tools/infrastructure/get-product-conventions.ps1 -EnvironmentName dev -AsHashtable
   $subProductName = 'App'
   @{
     ContainerApp = $dev.SubProducts[$subProductName]
     AvailabilityTest = $dev.SubProducts["$($subProductName)AvailabilityTest"]
     TrafficManager = $dev.SubProducts["$($subProductName)TrafficManager"]
   } | ConvertTo-Json -Depth 100
    ```


## 4. Add initial azure container app definition to infra-as-code bicep

1. Add new parameters to the [main.bicep](../tools/infrastructure/arm-templates/main.bicep) file:

   ```bicep
   param appFailoverExists bool = true
   param appPrimaryExists bool = true
   ```
      
   Name these parameters with a prefix to match the new app name. For example if your app was named `Template.Web`, then
   the parameters would be `webPrimaryExists` and `webFailoverExists`.
      
2. Copy existing [api.bicep](../tools/infrastructure/arm-templates/api.bicep) definition. Name the copy after the name 
   of your application. In our case that's app.bicep
   
3. Adapt the definition in this new app.bicep file as follows:
   * adjust the `appEnvVars` module to include any environment variables required by the app
     * **TIP**: pick names for these variables that start with a prefix to clearly separate from other apps in the solution (for our new project use `App__`)
   * adjust the `scaleRules` to match the expected scaling requirement for the app

4. Add to [main.bicep](../tools/infrastructure/arm-templates/main.bicep) the resources required for the new app
      
   * Copy the existing api module section starting `Template.Api` and rename `api` to `app` and `Api` to `App`
   * Adjust the shared settings for the azure container app to NOT enable custom domain (this will be enabled later). EG:
   
     ```bicep
     var appSharedSettings = {
       // SNIP
       isCustomDomainEnabled: false
       // isCustomDomainEnabled: settings.SubProducts.Aca.IsCustomDomainEnabled
     }
     ```

5. Add output variable for the managed identity of the new app

   Add the following to the output section of main.bicep, adjusting the output variable to match your app name:

   ```bicep
   @description('The Client ID of the Azure AD application associated with the MVC App managed identity.')
   output appManagedIdentityClientId string = appManagedId.properties.clientId
   ```
   
6. Assign RBAC role assignment and app role assignment to the new app managed identity

   This will depend on the access requirements for the new app. For example, if the app needs to read secrets from a key vault,
   then the managed identity will need to be assigned the `Key Vault Secrets User` role. If the app needs to access a  
   storage account, then the managed identity will need to be assigned the `Storage Blob Data Contributor` role, etc.

   Example: in main.bicep grant permission to read key secrets to new app's managed identity

   ```bicep
   module keyVault 'br/public:avm/res/key-vault/vault:0.11.0' = {
     name: '${uniqueString(deployment().name, location)}-KeyVault'
     params: {
       // SNIP
       roleAssignments: [
         { principalId: appManagedId.properties.principalId, roleDefinitionIdOrName: 'Key Vault Secrets User', principalType: 'ServicePrincipal' }
       ]
     }
   }
   ```
      
## 5. Adjust infra-as-code provisioning scripts

Extend [provision-azure-resources.ps1](../tools/infrastructure/provision-azure-resources.ps1) as follows
   
1. Print out the managed identity client id of the new app

   EG:

   ```pwsh
   Write-Information '  Creating desired resource state'
   # <SNIP>
   Write-Information "  INFO | App Managed Identity Client Id:- $($armResources.appManagedIdentityClientId.Value)"
   ```
   
2. Grant membership to required Entra-ID security groups

   EG:

   ```pwsh
   Write-Information '8. Set AAD groups - for resources (post-resource creation)...'
   # <SNIP>
   $dbCrudMembership = @(
       # <SNIP>
       @{
           ApplicationId       =   $armResources.appManagedIdentityClientId.Value
           Type                =   'ServicePrincipal'
       }
   )
   ```
   
3. Deploy initial azure container app infrastructure

   * To deploy from local dev machine
     (**note**: you will only be able to deploy in this way to your own Azure subscription and Azure Entra-ID tenant):

     ```pwsh
     # 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
     ./tools/infrastructure/provision-azure-resources.ps1 -InfA Continue -EnvironmentName dev -Login -SubscriptionId xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
     ```
   
   * Alternatively, push your changes to a branch, and manually run [Infrastructure CI/CD](../.github/workflows/infra-ci-cd.yml) github workflow selecting your branch
   
4. Verify the initial azure container app is running

   ```pwsh
   $dev = & "tools/infrastructure/get-product-conventions.ps1" -EnvironmentName dev -AsHashtable
   $subProductName = 'App'
   $aceDomain = (Get-AzContainerAppManagedEnv -ResourceGroupName $dev.AppResourceGroup.ResourceName -Name $dev.SubProducts.Aca.Primary.ResourceName).DefaultDomain
   $acaInfo = [ordered]@{
     ResourceGroup   = $dev.AppResourceGroup.ResourceName
     AcaEnvironment  = $dev.SubProducts.Aca.Primary.ResourceName
     Aca             = $dev.SubProducts[$subProductName].Primary.ResourceName
     Url           = ('https://{0}.{1}' -f $dev.SubProducts[$subProductName].Primary.ResourceName, $aceDomain)
   }
   [PsCustomObject]$acaInfo | fl *
   ```
   
   * Browse to the URL printed above to verify the app is running correctly. You should see the default asp.net core sample app page

## 6. Adjust dev deploy script to deploy new azure container app

1. Add new azure container app to the [deploy.ps1](../tools/dev-scripts/deploy.ps1) script

   * Copy the section `# ----------- Deploy API to Azure container apps -----------` adjusting for the new container app. 
     EG:

     ```pwsh
     # ----------- Deploy App to Azure container apps -----------
     $app = $convention.SubProducts.App
     $appParams = @{
       Name                =   $app.Primary.ResourceName
       ResourceGroup       =   $appResourceGroup
       Image               =   '{0}.azurecr.io/{1}:{2}' -f $convention.ContainerRegistries.Dev.ResourceName, $app.ImageName, $BuildNumber
       EnvVarsObject       =   @{
         'ApplicationInsights__AutoCollectActionArgs' = $true
       }
       HealthRequestPath   =   $app.DefaultHealthPath
       TestRevision        =   $true
     }
     $appAca = ./tools/dev-scripts/create-aca-revision.ps1 @appParams -InfA Continue -EA Stop
     ```

   * Print the url of the new container app. EG:

     ```pwsh
     Write-Host "App Url: https://$($appAca.configuration.ingress.fqdn)" -ForegroundColor Yellow
     ```

2. Deploy azure container app

   1. Build the solution, publishing docker image:

      ```pwsh
      az login
      # 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
      az account set --subscription xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
      ./tools/dev-scripts/build.ps1 -DockerPush -InfA Continue
      ```
      * **IMPORTANT**: You will need to have docker engine installed and running on your machine in order to build and push the images
      * When prompted for build number, enter value such as `0.0.7`, picking a value that is higher than the last build number
   
   2. Deploy solution stack:

      ```pwsh
      # IMPORTANT: You will likely need to connected to the office VPN in order to satisfy the firewall rules configured in the Azure SQL db
      # 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
      ./tools/dev-scripts/deploy.ps1 -InfA Continue -Login -SubscriptionId xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
      ````
   
      * When prompted for build number, enter the same value you provided above when building the solution

   3. Test that it worked by browsing to the "App Url" printed to the console

## 7. Update dev setup guide

Add a section to the [dev-setup.md](../docs/dev-setup.md) guide to explain how to configure and run new app for local 
development.

For an example section to add, see [dev-setup.md](../docs/dev-setup.md#app)

## 8. Update add environment guide

Add guidance to the [add-environment.md](../docs/add-environment.md) guide describing any configuration and secrets
required for the new app

## 9. Add app to the solution's CI/CD pipeline

1. Modify the 'Map variables' step in the [__Application Deployment](../.github/workflows/__app-deploy.yml) github workflow 
   to include the variables required for the new app. At minimum this will be:

   ```yml
   ".*": {
     # <SNIP>
     "gha_step_deploy_app_envVarsSelector": "App_*,ApplicationInsights_*",
     "gha_step_deploy_app_imageToDeploy": "${{ inputs.docker-registry }}/${{ env.Convention_SubProducts_App_ImageName }}:${{ inputs.docker-image-tag }}"
     # <SNIP>
   }
   ```
   
2. Deploy the new azure container app to both the primary and failover ACA environments:

   1. Copy the existing 'Deploy App to Azure container apps' step in the pipeline and adjust for the new app. EG:

      ```yml
      - name: Deploy App (primary region)
        uses: christianacca/container-apps-revision-action@v1
        with:
        containerAppName: ${{ env.Convention_SubProducts_App_Primary_ResourceName }}
        envVarsSelector: ${{ env.gha_step_deploy_app_envVarsSelector }}
        envVarKeyTransform: _=>__
        healthRequestPath: ${{ env.Convention_SubProducts_App_DefaultHealthPath }}
        imageToDeploy: ${{ env.gha_step_deploy_app_imageToDeploy }}
        resourceGroup: ${{ env.Convention_AppResourceGroup_ResourceName }}
        testRevision: true
      
      - name: Deploy App (failover region)
        if: ${{ env.Convention_SubProducts_App_Failover_ResourceName != null }}
        uses: christianacca/container-apps-revision-action@v1
        with:
        containerAppName: ${{ env.Convention_SubProducts_App_Failover_ResourceName }}
        envVarsSelector: ${{ env.gha_step_deploy_app_envVarsSelector }}
        envVarKeyTransform: _=>__
        healthRequestPath: ${{ env.Convention_SubProducts_App_DefaultHealthPath }}
        imageToDeploy: ${{ env.gha_step_deploy_app_imageToDeploy }}
        resourceGroup: ${{ env.Convention_AppResourceGroup_ResourceName }}
        testRevision: true
      ```
      
   2. Commit the changes and push to PR branch
      * The changes made to the workflow will NOT yet be executed. Only the initial build, test and publish steps will be executed
   3. Manually run the [Application CI/CD](../.github/workflows/app-ci-cd.yml) github workflow selecting the PR branch
      * This will execute the deployment steps for the new app

## 10. Implement custom domain for the new app

1. Create DNS records for the new app

   DNS records need to be created for the new azure container app for every environment it is deployed to. To find out
   the records that need to be created, run the following command, substituting the `Component` parameter with the name
   you set up in the `get-product-conventions.ps1` script:

   ```pwsh
   ./tools/infrastructure/print-custom-dns-record-table.ps1 -Component 'App' -Login
   ```

   For more information on this see the section "Register DNS records" in the [deploy-app.md](./deploy-app.md#register-dns-records) guide.

2. Adjust the [main.bicep](../tools/infrastructure/arm-templates/main.bicep) file to enable custom domain for the new app

   To do this, replace the hard coded value of `isCustomDomainEnabled` in the main.bicep. EG:

   ```bicep
   var appSharedSettings = {
   // SNIP
     isCustomDomainEnabled: settings.SubProducts.Aca.IsCustomDomainEnabled
   }
   ```

3. Deploy initial azure container app infrastructure

   * To deploy from local dev machine
     (**note**: you will only be able to deploy in this way to your own Azure subscription and Azure Entra-ID tenant):
   
     ```pwsh
     # 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
     ./tools/infrastructure/provision-azure-resources.ps1 -InfA Continue -EnvironmentName dev -Login -SubscriptionId xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
     ```
   
   * Alternatively, push your changes to your PR branch, and manually run [Infrastructure CI/CD](../.github/workflows/infra-ci-cd.yml) github workflow selecting your PR branch

4. Verify the custom domain is correctly configured

   ```pwsh
   $dev = & "tools/infrastructure/get-product-conventions.ps1" -EnvironmentName dev -AsHashtable
   $subProductName = 'App'
   $acaInfo = [ordered]@{
     ResourceGroup   = $dev.AppResourceGroup.ResourceName
     AcaEnvironment  = $dev.SubProducts.Aca.Primary.ResourceName
     Aca             = $dev.SubProducts[$subProductName].Primary.ResourceName
     Url           = ('https://{0}{1}' -f $dev.SubProducts.App.HostName, $dev.SubProducts.App.Primary.DefaultHealthPath)
   }
   [PsCustomObject]$acaInfo | fl *
   ```

    * Browse to the URL printed above to verify the custom domain is resolving to the app, and the app it is able to respond to the health check