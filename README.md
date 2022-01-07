# Starter project for an API project

## Overview

Clone this repo and copy the solution to kickstart the effort of creating a new API

## Architecture and Project structure

See [document](docs/architecture-and-project-structure.md)

## Connecting to Azure from local machine

1. Establish an authenticated session with Azure with any of the following tools:
   * Visual Studio
   * Visual Studio Code
   * Azure CLI (`az login`)
   * Powershell (`Connect-AzAccount`)
2. Modify appsettings as detailed below either by using dotnet user-secrets (preferred) or directly in appsettings.Development.json file.

### appsettings

* API + Function app -> Azure SQL: 
  * `ConnectionStrings__AppDatabase`: `Server=<your_sql_server>.database.windows.net; Database=<your_db_name>; Authentication=Active Directory Default;`
* API -> Azure function app:
  * `Api__FunctionsAppToken__Audience`: set this to the value of the App/Client ID of the Azure AD App registration associated with the function app
  * `Api__ReverseProxy__Clusters__FunctionsApp__Destinations__Primary__Address`: set this to the public url of the Azure function app

**IMPORTANT**: 
currently there is a problem connecting the API running on a dev machine to Azure functions. 
A support ticket with Microsoft has been opened to resolve this


## Deploying the stack

**IMPORTANT** the initial helm chart in this repo makes some assumptions around ingress. It assumes that the AKS cluster has implemented
[HTTP application routing](https://docs.microsoft.com/en-us/azure/aks/http-application-routing). If you don't have access to creating
a test aks cluster as per instructions below, then you will not be able to hit the API over the internet.

**IMPORTANT** When moving to production you will need to replace the ingress rules in the helm chart to use a production ready ingress (eg nginx).

### Prerequisites

* [az-cli](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli), required to:
  * enable/add pod identity
  * run dev scripts
* powershell (scripts tested on powershell core, although windows powershell will likely work!)
* docker engine to run the dev script with the flag `-DockerPush`

### Deploy steps

**NOTE**: If you're not deploying the starter project itself, then you will need to change the [`ProductName` setting](tools/infrastructure/get-product-conventions.ps1)

1. (Once-only) Setup shared infrastructure:
   1. Provision AKS. See section below "Create a test AKS cluster"
   2. Enable Pod identity (aka managed identity for pods): `./tools/infrastructure/enable-aks-pod-identity.ps1 -InfA Continue -Login`
2. (When changed) Provision Azure resources: `./tools/infrastructure/provision-azure-resources.ps1 -InfA Continue -Login`
   * NOTE: if this script fails try running it again (script is idempotent)
   * **IMPORTANT**: If a secondary (failover) Azure SQL server is provisioned - see troubleshooting section below
3. (Once-only) Add Pod identity for API app: `./tools/infrastructure/add-aks-pod-identity.ps1 -InfA Continue`
4. Build App: `./tools/dev-scripts/build.ps1 -DockerPush -InfA Continue`
   * **IMPORTANT**: You will need to have docker engine installed and running on your machine in order to build and push the images
5. Deploy App: `./tools/dev-scripts/deploy.ps1 -InfA Continue`
6. Test that it worked:
   * browse to the "Api health Url" printed to the console
   * Import the postman [collection](tests/postman/api.postman_collection.json) and [environment](tests/postman/api-local.postman_environment.json), 
     change the baseUrl postman variable to the "Api Url" printed to the console. Run the requests in the collection

### Troubleshooting `provision-azure-resources.ps1`

When running `provision-azure-resources.ps1`, you might receive an error with the following message:

```cmd
Login failed for user '<token-identified principal>'
```

To resolve the problem try re-running the provisioning script again (it's safe to do so). This still may not work if the script
is provisioning a secondary Azure SQL server as part of a failover group. In this case, try waiting for somewhere between 15-60 minutes and re-run the script.
It appears that the creation of the replicated database takes sometime and is cause of the problem.

## Cleanup

To remove all Azure resources and AKS pod identity: `./tools/infrastructure/deprovision-azure-resources.ps1 -UninstallAksApp`

## Create a test AKS cluster

Use the azure portal as described in this article: https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough-portal

Use the following setting values:

* Basics:
    * Cluster details > Cluster preset configuration: Dev/Test
    * Primary node pool > Node count: 1
* Node pools: accept defaults
* Networking:
    * Network configuration: Azure CNI
    * Http application routing: Yes
* Integrations:
    * container registry: create new