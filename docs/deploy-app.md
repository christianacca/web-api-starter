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

**IMPORTANT** the initial helm chart in this repo makes some assumptions around ingress. It assumes that the AKS cluster has implemented
[HTTP application routing](https://docs.microsoft.com/en-us/azure/aks/http-application-routing). If you don't have access to creating
a test aks cluster as per instructions below, then you will not be able to hit the API over the internet.

**IMPORTANT** When moving to production you will need to replace the ingress rules in the helm chart to use a production ready ingress (eg nginx).


## Deploying (full-stack) locally from dev machine

### Prerequisites

* [az-cli](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli), required to:
    * enable/add pod identity
    * run dev scripts
* powershell core
* docker engine to run the dev script with the flag `-DockerPush`

### Permissions to run infrastructure scripts

You are unlikely to have permissions to run the infrastructure provisioning scrips (steps 1-3 below) from your dev machine :-(
In practice the only way to run these scripts from a dev machine is:

1. To have your own Azure subscription where you are the owner, AND
2. The Azure subscription is linked to a developer Azure AD tenant created using the Microsoft 365 developer program. See the following on how to get this setup:
    1. sign-up for the MS 365 developer program: <https://developer.microsoft.com/en-us/microsoft-365/dev-program>
    2. linking your VS subscription to your office365 dev tenant: <https://laurakokkarinen.com/how-to-use-the-complimentary-azure-credits-in-a-microsoft-365-developer-tenant-step-by-step/>
    3. things to be aware of when moving your VS subscription to another AD tenant: <https://docs.microsoft.com/en-us/azure/role-based-access-control/transfer-subscription>

If you don't have access to an isolated developer Azure AD tenant, then you will need to run the provisioning scripts via the github workflows in this repo.

For more information on setting up these github workflows for your project see: [create-github-actions-infrastructure-pipeline](create-github-actions-infrastructure-pipeline.md)

### Steps

**NOTE**: If you're not deploying the starter project itself, then you will need to change the [`ProductName` setting](../tools/infrastructure/get-product-conventions.ps1)

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
    * Import the postman [collection](../tests/postman/api.postman_collection.json) and [environment](../tests/postman/api-local.postman_environment.json),
      change the baseUrl postman variable to the "Api Url" printed to the console. Run the requests in the collection

### Create a test AKS cluster

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


## Deploying from CI/CD

1. Make sure the github workflow has been setup as per the guide: [create-github-actions-infrastructure-pipeline](create-github-actions-infrastructure-pipeline.md)
2. Make sure that the github workflow [Deploy Infrastructure](../.github/workflows/deploy-infrastructure.yml) has run successfully at least once for the environment you want to deploy the app to
3. Run the [Add AKS pod-identity](../.github/workflows/add-aks-pod-identity.yml) github workflow **ONCE** only for environments that the infrastructure has been deployed to:
   1. Go to the Actions tab in the github repo
   2. Manually run the workflow 'Add AKS pod-identity', selecting the name of the environment to deploy to
4. Make sure to comment back in the CI/CD triggers in the github workflow that deploys the app (todo: add an example workflow)


## Cleanup

To remove all Azure resources and AKS pod identity run the deprovision-azure-resources.ps1 script from a powershell prompt (assuming you have permissions),
or running the github workflow [Uninstall Infrastructure](../.github/workflows/uninstall-infrastructure.yml)

### From a powershell prompt

```powershell
./tools/infrastructure/deprovision-azure-resources.ps1 -UninstallAksApp -UninstallDataResource -DeleteResourceGroup -DeleteSqlAADGroups -Environment xxx  -InfA Continue -Login
```

### From the github workflow

1. Go to the Actions tab in the github repo
2. Manually run the workflow 'Uninstall Infrastructure', selecting the name of the environment to deploy to


## Troubleshooting `provision-azure-resources.ps1`

When running `provision-azure-resources.ps1`, you might receive an error with the following message:

```cmd
Login failed for user '<token-identified principal>'
```

To resolve the problem try re-running the provisioning script again (it's safe to do so). This still may not work if the script
is provisioning a secondary Azure SQL server as part of a failover group. In this case, try waiting for somewhere between 15-60 minutes and re-run the script.
It appears that the creation of the replicated database takes sometime and is cause of the problem.