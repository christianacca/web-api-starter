# Instructions for adding a new application to the solution

[!IMPORTANT]
For the purposes of this guide, the name of the MVC web application will be Template.App. For your app, pick a name that
is suitable for your solution. Once selected use that name in place of Template.App in the following instructions.

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
       <TargetFramework>net8.0</TargetFramework>
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

## 2. Add docker support

[!NOTE]
We are NOT going to add the dotnet tooling support for docker. This is because we are not using docker for "inner-loop" development.
We're just need to define our preferred docker base image

1. Add Dockerfile file 

   add file src/Template.App/Dockerfile with the following definition:

   ```yaml
   FROM mcr.microsoft.com/dotnet/aspnet:8.0-noble-chiseled-extra # <- change '8.0' to the version of the .net you are targeting
   #EXPOSE 8080 <- this is the default port that a .net 8+ application will be configured to listen on and is the port exposed in the base docker image
   
   WORKDIR /app
   
   ENTRYPOINT ["dotnet", "Template.App.dll"]
   COPY . .
   ```

2. Add .dockerignore file

   add file src/Template.App/.dockerignore with the following definition:

   ```plaintext
   Dockerfile
   ```


## 3. Extend infra-as-code conventions for new app

1. Add app created above to [get-product-conventions.ps1](../tools/infrastructure/get-product-conventions.ps1)

   EG:

   ```pwsh
   App                 = @{
       AdditionalManagedId = 'AcrPull'
       Type = 'AcaApp'
   }
   ```

   To see the new app conventions:

   ```pwsh
   (./tools/infrastructure/get-product-conventions.ps1 -EnvironmentName dev -AsHashtable).SubProducts.App | ConvertTo-Json
    ```


## 4. Add initial azure container app definition to infra-as-code bicep

1. Add new parameters to the main.bicep file:

   ```bicep
   param appPrimaryExists bool = true
   param appFailoverExists bool = true
   ```
      
   Name these parameters with a prefix to match the new app name. For example if your app was named `Template.Web`, then
   the parameters would be `webPrimaryExists` and `webFailoverExists`.
      
2. Copy existing api.bicep definition. Name the copy after the name of your application. In our case that's app.bicep
   
3. Adapt the definition in this new app.bicep file as follows:
   * adjust the `appEnvVars` module to include any environment variables required by the app
     * **TIP**: pick names for these variables that start with a prefix to clearly separate from other apps in the solution (for our new project use `App__`)
   * adjust the `scaleRules` to match the expected scaling requirement for the app

4. Add to main.bicep the azure container app module and managed identity for the app
      
   * Copy the existing api module section starting and end `Template.Api` and rename `api` to `app` and `Api` to `App`
   * Adjust the shared settings for the azure container app to NOT enable custom domain (this will be enabled later). EG:
   
     ```bicep
     var appSharedSettings = {
       // SNIP
       isCustomDomainEnabled: false
       // isCustomDomainEnabled: settings.SubProducts.Aca.IsCustomDomainEnabled
     }
     ```

5. Add output variable for the managed identity of the new app

   Add the following to the output section of main.bicep, adjusting the name as needed:

   ```bicep
   @description('The Client ID of the Azure AD application associated with the MVC App managed identity.')
   output appManagedIdentityClientId string = appManagedId.properties.clientId
   ```
   
6. Assign RBAC role assignment and app role assignment to the new app managed identity

   This will depend on the access requirements for the new app. For example, if the app needs to secrets from a key vault, then
   the managed identity will need to be assigned the `Key Vault Secrets User` role. If the app needs to access a storage account,
   then the managed identity will need to be assigned the `Storage Blob Data Contributor` role, etc.

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

1. Gather the bicep deployment variables for the new app and add these to the bicep `TemplateParameterObject`

   EG:

   ```pwsh
   Write-Information "  Gathering existing resource information..."
   $mainArmTemplateParams = @(
       # <SNIP>
       Get-AcaAppInfoVars $convention -SubProductName App
   )
   ```
   
2. Print out the managed identity client id of the new app

   EG:

   ```pwsh
   Write-Information '  Creating desired resource state'
   # <SNIP>
   Write-Information "  INFO | App Managed Identity Client Id:- $($armResources.appManagedIdentityClientId.Value)"
   ```
   
3. Grant membership to required Entra-ID security groups

   EG:

   ```pwsh
   Write-Information '8. Set AAD groups - for resources (post-resource creation)...'
   
   # <SNIP>
   
   $dbCrudMembership = @(
       @{
           ApplicationId       =   $armResources.appManagedIdentityClientId.Value
           Type                =   'ServicePrincipal'
       }
   )
   ```
   
4. Deploy new azure container app

   ```pwsh
   # 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
   ./tools/infrastructure/provision-azure-resources.ps1 -InfA Continue -EnvironmentName dev -Login -SubscriptionId xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
   ```
   
5. Verify the initial azure container app is running

   

   ```pwsh
   $dev = & "tools/infrastructure/get-product-conventions.ps1" -EnvironmentName dev -AsHashtable
   $subProductName = 'App' # <- IMPORTANT: change to the name of the sub-product you are verifying
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
   