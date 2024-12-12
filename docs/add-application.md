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

## 3. Extend infra-as-code to deploy new app

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