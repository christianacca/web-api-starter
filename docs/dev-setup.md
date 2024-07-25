# Local dev setup

The steps below are written to run everything from the command-line. When first setting up on a developer machine, make sure to run through these steps as prescribed.
Once up and running, feel free to then switch to running the projects via an IDE such as Visual Studio 2022 or Jetbrains Rider (see section below).

> **IMPORTANT**: all commands (at the command-line) mentioned below assume that they are run from the root of the directory containing the solution (.sln) file.
> All folder and file paths mentioned in the commands below assume you are running powershell core which understand forward slashes (eg ./my-folder/)

## Initial setup

1. Ensure you have dotnet sdk for .net 8 installed (to see what's installed: `dotnet --list-sdks`)
2. For windows machines ensure you have installed [chocolotey](https://docs.chocolatey.org/en-us/choco/setup#installing-chocolatey-cli)
3. Ensure you have powershell core with a minimum version of 6.2 installed:
    * check version: `pwsh --version` - if this fails to find the command or is less the 6.2, then install:
        * windows: `choco install powershell-core`
        * mac: `brew install --cask powershell`
4. Install az-cli (you'll use this to sign-in to azure)
    * mac: `brew update && brew install azure-cli`
    * windows: `choco install azure-cli` (note: you to restart command prompt after installation)
5. Install postman
    * mac: `brew install --cask postman`
    * windows: `choco install postman` (or manually download and install from <https://www.postman.com/downloads/>)
6. Install Azure functions core tools
    * windows: `choco install azure-functions-core-tools`
    * mac: `brew tap azure/functions && brew install azure-functions-core-tools@4`
7. Clone the repo: `git clone https://github.com/christianacca/web-api-starter.git`
    * **Tip**: prefer to clone to a directory that keep path short and avoid spaces. For example: `C:\git\` or `~/git/`
8. Follow guide "[Grant access to Azure dev environment](#grant-access-to-azure-dev-environment)" below.
    * This will ensure that when running locally, the api and function app will have access to keyvault to retrieve secrets required for certain runtime operations like:
        * authenticating to xmla endpoints for when running report deployments
        * authenticating to central identity for when adding new users
    * If you are unable to be granted access to Azure, you can still run code locally, albeit limited functionality,
      but you will have to disable keyvault integration by running the following commands
        * api: `dotnet user-secrets set Api:KeyVaultDisabled true --id d4101dd7-fec4-4011-a0e8-65748f7ee73c`
        * functions: `dotnet user-secrets set InternalApi:KeyVaultDisabled true --id 1c30ae06-8c59-4fff-bf49-c7be38e7e23b`
9. Ensure you have a SQL Server instance you have access to (preferably a local one):
    * windows: use localdb which will be installed by Visual Studio by default
        * note: make sure to have installed 2019 or greater version of localdb
        * you can check your version by running `SqlLocalDB v`
    * mac: use docker to run MS SQL Server 2019 or greater
10. Install Azure credentials provider:
    * windows: `iex "& { $(irm https://aka.ms/install-artifacts-credprovider.ps1) }"`
    * mac: `sh -c "$(curl -fsSL https://aka.ms/install-artifacts-credprovider.sh)"`
    * for more details on installation see: <https://github.com/microsoft/artifacts-credprovider#setup>

## API

1. Login to Azure using az-cli using your mri username/password:
   ```pwsh
   # zfbl5.onmicrosoft.com (Christian's dev AD tenant): 77806292-ec65-4665-8395-93cb7c9dbd36
   az login --tenant xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx --allow-no-subscriptions
   ```
2. Restore nuget packages from azure artifacts:
   * `dotnet restore --interactive`
   * follow onscreen prompts to sign-in using the device flow
3. Install dotnet local tools: `dotnet tool restore`
4. Trust the .net dev certificate
    * `dotnet dev-certs https --trust`
    * Accept any prompts
5. Ensure connection string is pointing to the SQL Server instance
   * Review the connection string in Api/appsettings.Development.json
     (**tip**: the default is intended to work with localdb installed by Visual Studio on a windows machine)
   * Adjust as necessary to connect to your SQL Server instance
      * use dotnet user-secrets tool rather than modifying appsettings.Development.json file directly
      * EG:  `dotnet user-secrets set Api:ConnectionStrings:AppDatabase 'Data Source=(localdb)\YOURINSTANCE;Initial Catalog=web-api-starter;Integrated Security=True;TrustServerCertificate=true;' --id d4101dd7-fec4-4011-a0e8-65748f7ee73c`
      * **tip**: if you're using Visual Studio or Jetbrains Rider, you can use the built-in user-secrets tool to set the connection string.
        But note that any forward slash will need to be escaped by adding another forward slash eg `\\`
6. Start/Run the API project: `dotnet run --project ./src/Template.Api`
7. Check that the basics are running by browsing to: <https://localhost:5000/health>

## Functions App

1. If not already, login to Azure using az-cli using your mri username/password. EG:
   ```pwsh
   # zfbl5.onmicrosoft.com (Christian's dev AD tenant): 77806292-ec65-4665-8395-93cb7c9dbd36
   az login --tenant xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx --allow-no-subscriptions
   ```
2. Enable API -> function app messaging by modifying appsettings in the _Api project_:
    * run:  `dotnet user-secrets set Api:DevFeatureFlags:EnableQueues true --id d4101dd7-fec4-4011-a0e8-65748f7ee73c`
3. Ensure connection string in the _Functions project_ is pointing to the SQL Server instance
   * Review the connection string in Functions/appsettings.Development.json
     (**tip**: the default is intended to work with localdb installed by Visual Studio on a windows machine)
   * Adjust as necessary to connect to your SQL Server instance:
      * use dotnet user-secrets tool rather than modifying appsettings.Development.json file directly
      * EG:  `dotnet user-secrets set InternalApi:ConnectionStrings:AppDatabase 'Data Source=(localdb)\YOURINSTANCE;Initial Catalog=web-api-starter;Integrated Security=True;TrustServerCertificate=true;' --id 1c30ae06-8c59-4fff-bf49-c7be38e7e23b`
      * **tip**: if you're using Visual Studio or Jetbrains Rider, you can use the built-in user-secrets tool to set the connection string.
        But note that any forward slash will need to be escaped by adding another forward slash eg `\\`
4. Build functions app: `dotnet build ./src/Template.Functions`
5. Ensure Azurite is running at the command-line as explained [here](../tools/azurite/README.md#install-and-run-for-command-line)
6. Run functions app:
    * change current directory: `cd ./src/Template.Functions/bin/Debug/net8.0`
    * run: `func start`
7. Check that the basics are running by calling function directly by browsing to: <http://localhost:7071/api/Echo>
8. Check API -> Functions app via postman:
    1. Import the postman collection [api.postman_collection.json](../tests/postman/api.postman_collection.json)
    2. Import the postman environment [api-local.postman_environment.json](../tests/postman/api-local.postman_environment.json)
    3. Run the requests "GetUser Function" in the collection "MRI Web API Starter>Proxied"


## Running the API and Functions app from VS2022

**IMPORTANT** The steps below assume you have already followed the section above once already for running the API and functions app from the command-line

1. Configure multiple startup projects:
   * Template.Api
   * Template.Functions
2. Run Azurite at the command line as explained here: [here](../tools/azurite/README.md#install-and-run-for-command-line)
3. Start with debugging (F5)

If you find you are getting an error restoring nuget packages, then likely your credentials you sign-in to VS2022 need refreshing. To do that:

1. Go to: Help > Register Visual Studio
2. Re-enter your credentials / sign-in again


## Grant access to Azure dev environment

To be able to connect to Azure services for this project you will need to be granted access. You will want access to the dev environment in Azure in
order to integrate with Azure keyvault. This will allow you to develop locally without having to add user-secrets for things like central identity password and pbi
authentication credentials.

1. open the github workflow [Infrastructure Grant Azure Environment Access](../.github/workflows/infra-grant-azure-env-access.yml)
2. select the "Run workflow" button
3. select the environment to grant access to and the level:
    * Environment: dev
    * Access level: development
4. in the 'User to grant' add your email address
5. select the "Run workflow" button


## Connecting to Azure from local machine

Typically you will want to be running local emulators for any Azure service (see above instructions). Only follow these next steps for those occasions you require 
to connect your dev machine to Azure cloud services instead.

1. Follow the section "Grant access to Azure environment" above
2. Establish an authenticated session by login to Azure with Azure CLI:
   ```pwsh
   # zfbl5.onmicrosoft.com (Christian's dev AD tenant): 77806292-ec65-4665-8395-93cb7c9dbd36
   az login --tenant xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx --allow-no-subscriptions
   ```
3. Modify appsettings.Development.json as detailed below using dotnet user-secrets

### appsettings

The following values will work for the [dev](https://github.com/MRI-Software/data-services-gateway/deployments/activity_log?environment=dev) environment 
[deployed to Azure](https://portal.azure.com/#@MRISOFTWARE.onmicrosoft.com/resource/subscriptions/c398eb55-b057-45f9-8fe3-cfb0034418f5/resourceGroups/rg-dev-aig-eastus/overview)

* API + Function app -> Azure SQL:
    * `dotnet user-secrets set Api:ConnectionStrings:AppDatabase 'Server=clcdevwas01eastus.database.windows.net; Database=clcdevwas01; Authentication=Active Directory Default;' --id d4101dd7-fec4-4011-a0e8-65748f7ee73c`
    * `dotnet user-secrets set InternalApi:ConnectionStrings:AppDatabase 'Server=clcdevwas01eastus.database.windows.net; Database=clcdevwas01; Authentication=Active Directory Default;' --id 1c30ae06-8c59-4fff-bf49-c7be38e7e23b`
* API -> Azure function app:
    * `dotnet user-secrets set Api:FunctionsAppToken:Audience 'api://func-clc-was-dev-internalapi/.default' --id d4101dd7-fec4-4011-a0e8-65748f7ee73c`
    * `dotnet user-secrets set Api:ReverseProxy:Clusters:FunctionsApp:Destinations:Primary:Address 'https://func-clc-was-dev-internalapi.azurewebsites.net' --id d4101dd7-fec4-4011-a0e8-65748f7ee73c`
    * `dotnet user-secrets set Api:FunctionsAppQueue:ServiceUri 'https://funcsa68efed087a1b0.queue.core.windows.net' --id d4101dd7-fec4-4011-a0e8-65748f7ee73c`
* Function App -> Blob storage:
    * `dotnet user-secrets set InternalApi:ReportBlobStorage:ServiceUri 'https://pbireport68efed087a1b0.blob.core.windows.net/' --id 1c30ae06-8c59-4fff-bf49-c7be38e7e23b`
