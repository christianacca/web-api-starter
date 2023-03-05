# Deploying the app

## Overview

At a high level deployment consists of:

1. Setting up the AKS cluster to support pod-identity
2. Deploying the infrastructure required for the app
3. Deploying the app into the infrastructure

This repo comes with infrastructure-as-code (IaC) scripts that perform steps 1 and 2. These scripts are designed to be run from your dev machine, or from a CI/CD pipeline.
This repo has an example CI/CD pipeline written as a series of github workflows that run these IaC scripts.

There is also dev scripts that can be used to deploy the app into the provisioned Azure infrastructure from local dev machine.

In the future, there will be an example CI/CD pipeline written as a github workflow for deploying the app.


## Deploying (infrastructure + app) locally from dev machine

### Prerequisites

* [az-cli](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (**minimum vs 2.39.0**), required to:
    * enable/add pod identity
    * run dev scripts
* [Azure bicep cli](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install#install-manually)
* powershell core (tested on v7.2)
* docker engine to run the dev script with the flag `-DockerPush`

### Permissions to run infrastructure scripts

You are unlikely to have permissions to run the infrastructure provisioning scrips (steps 1-3 below) from your dev machine :-(
In practice the only way to run these scripts from a dev machine is:

1. To have your own Azure subscription where you are the owner, AND
2. The Azure subscription is linked to a developer Azure AD tenant created using the Microsoft 365 developer program. See the following on how to get this setup:
    1. sign-up for the MS 365 developer program: <https://developer.microsoft.com/en-us/microsoft-365/dev-program>
    2. linking your VS subscription to your office365 dev tenant: <https://laurakokkarinen.com/how-to-use-the-complimentary-azure-credits-in-a-microsoft-365-developer-tenant-step-by-step/>
    3. things to be aware of when moving your VS subscription to another AD tenant: <https://docs.microsoft.com/en-us/azure/role-based-access-control/transfer-subscription>


### Steps

1. (Once-only) Modify product conventions to avoid conflicts for those azure resource whose names are globally unique:
   1. open [get-product-conventions.ps1](../tools/infrastructure/get-product-conventions.ps1)
   2. set `ProductName` (line 20) to make it globally unique (adding your initials eg `-cc` as a prefix should be sufficient)
   3. comment out the line `Get-ResourceConvention @conventionsParams -AsHashtable:$AsHashtable`
   4. comment-in the block of code that starts `# If you need to override conventions, ...`
   5. set the `RegistryName` to make it globally unique (adding your initials eg `cc` as a prefix should be sufficient)
2. (Once-only) Setup shared infrastructure:
   1. Provision AKS. See "Permissions to run infrastructure scripts" above for reason this is necessary
      ```pwsh
      # 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
      ./tools/infrastructure/add-aks-cluster.ps1 -InfA Continue -EnvironmentName dev -CreateAzureContainerRegistry -Login -SubscriptionId xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
      ````
   2. Enable Pod identity (aka managed identity for pods):
      ```pwsh
      # 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
      ./tools/infrastructure/enable-aks-pod-identity.ps1 -InfA Continue -EnvironmentName dev -Login -Subscription xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
      ````
3. (When changed) Provision Azure resources:
   ```pwsh
      # 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
      ./tools/infrastructure/provision-azure-resources.ps1 -InfA Continue -EnvironmentName dev -Login -Subscription xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
      ````
    * NOTE: if this script fails try running it again (script is idempotent)
    * **IMPORTANT**: If a secondary (failover) Azure SQL server is provisioned - see troubleshooting section below
4. (Once-only) Add Pod identity for API app:
   ```pwsh
      # 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
      ./tools/infrastructure/add-aks-pod-identity.ps1 -InfA Continue -EnvironmentName dev -Login -Subscription xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
      ````
5. Build App: `./tools/dev-scripts/build.ps1 -DockerPush -InfA Continue`
    * **IMPORTANT**: You will need to have docker engine installed and running on your machine in order to build and push the images
6. Deploy App: 
   ```pwsh
      # 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
      ./tools/dev-scripts/deploy.ps1 -InfA Continue -Login -Subscription xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
      ````
7. Test that it worked:
    * browse to the "Api health Url" printed to the console
    * Import the postman [collection](../tests/postman/api.postman_collection.json) and [environment](../tests/postman/api-local.postman_environment.json),
      change the baseUrl postman variable to the "Api Url" printed to the console. Run the requests in the collection


## Cleanup

To remove all Azure resources and AKS pod identity run the deprovision-azure-resources.ps1 script from a powershell prompt (assuming you have permissions)

```pwsh
# 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
./tools/infrastructure/deprovision-azure-resources.ps1 -InfA Continue -Environment xxx -UninstallAksApp -DeleteAADGroups -Login -Subscription xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
```

## Troubleshooting `provision-azure-resources.ps1`

When running `provision-azure-resources.ps1`, you might receive an error with the following message:

```cmd
Login failed for user '<token-identified principal>'
```

To resolve the problem try re-running the provisioning script again (it's safe to do so). This still may not work if the script
is provisioning a secondary Azure SQL server as part of a failover group. In this case, try waiting for somewhere between 15-60 minutes and re-run the script.
It appears that the creation of the replicated database takes sometime and is cause of the problem.