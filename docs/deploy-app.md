# Deploying the app

<!-- TOC -->
* [Deploying the app](#deploying-the-app)
  * [Overview](#overview)
  * [Infrastructure](#infrastructure)
  * [Deploying infrastructure using CI/CD](#deploying-infrastructure-using-cicd)
    * [Deploying infra for the FIRST TIME](#deploying-infra-for-the-first-time)
    * [Deploying infra from CI/CD](#deploying-infra-from-cicd)
  * [Deploying app from CI/CD](#deploying-app-from-cicd)
  * [Granting access to Azure resources](#granting-access-to-azure-resources)
    * [Steps](#steps)
    * [Revoking access to Azure resources](#revoking-access-to-azure-resources)
    * [Azure environment Access levels](#azure-environment-access-levels)
  * [Deploying (infrastructure + app) locally from dev machine](#deploying--infrastructure--app--locally-from-dev-machine)
    * [Prerequisites](#prerequisites)
    * [Permissions to run infrastructure scripts](#permissions-to-run-infrastructure-scripts)
    * [Steps](#steps-1)
  * [Cleanup](#cleanup)
    * [From a powershell prompt](#from-a-powershell-prompt)
    * [From the github workflow](#from-the-github-workflow)
  * [Troubleshooting `provision-azure-resources.ps1`](#troubleshooting-provision-azure-resourcesps1)
<!-- TOC -->

## Overview

At a high level deployment consists of:

1. Setting up the AKS cluster to support pod-identity (see section ["Deploying infra for the FIRST TIME"](#deploying-infra-for-the-first-time))
2. Deploying the infrastructure required for the app (see section ["Deploying infra from CI/CD"](#deploying-infra-from-cicd))
3. Deploying the app into the infrastructure (see section ["Deploying app from CI/CD"](#deploying-app-from-cicd))
4. Grant access to the teams members to the resources in Azure for the environment (see section ["Granting access to Azure resources"](#granting-access-to-azure-resources))

This repo contains various powershell scripts (see [tools directory](../tools)) that can be run from the command-line to automate the deployment tasks above 
and [github workflows](../.github/workflows) that automate CI/CD pipelines for the same deployments.

For more information on how these github workflows for the project were set up: [create-github-actions-infrastructure-pipeline](create-github-actions-infrastructure-pipeline.md)

## Infrastructure

> Note: Image represents deployment to the dev environment. 
> Other environments will have the same resources but with different names, plus production and qa environments will also have failover instances for SQL and AKS pods

**TODO: Add image describing infrastructure deployment**

> Also see output from [print-product-convention-table.ps1](../tools/infrastructure/print-product-convention-table.ps1)

## Deploying infrastructure using CI/CD

> **TIP**: to discover the configuration values used during deployment run: `./tools/infrastructure/get-product-conventions.ps1`

### Deploying infra for the FIRST TIME

1. Every environment: Enable Pod identity (aka managed identity for pods)
   1. Manually run the workflow [Infrastructure Enable AKS Pod-identity](../.github/workflows/infra-enable-aks-pod-identity.yml), selecting the name of the environment to deploy to (for example dev)
      ![run workflow](./assets/infra-enable-aks-pod-id-run-workflow.png)
   2. For all environments except dev you will need to [approve deployment](https://docs.github.com/en/actions/managing-workflow-runs/reviewing-deployments)
2. Deploy to dev and qa environment:
   1. Touch any file in tools/infrastructure on the `master` (via a PR), *or* manually run [Infrastructure CI/CD](../.github/workflows/infra-ci-cd.yml) workflow
   2. Deploy to dev: [Infrastructure CI/CD](../.github/workflows/infra-ci-cd.yml) workflow will trigger *automatically* to deploy infrastructure to dev (ie you don't need to do anything)
   3. Deploy to qa: once deployed to the dev environment, the [Infrastructure CI/CD](../.github/workflows/infra-ci-cd.yml) workflow will queue up a deployment for the infrastructure to the qa environment.
      ![queued deployment](./assets/infra-ci-queued.png)
      This deployment will need to be reviewed then [approved in github](https://docs.github.com/en/actions/managing-workflow-runs/reviewing-deployments)
3. Deploy to demo, staging, prod-xxx environments:
   1. Go to the [Releases list](https://github.com/MRI-Software/web-api-starter/releases) in the github repo
   2. Find the pre-release that you want to deploy, it will start with 'infra-master-' or 'infra-release-'
      ![infra release](./assets/infra-release.png)
   3. To deploy the release, select the 'Edit' option, **_uncheck_** 'Set as pre-release', and then select 'Update release'. This will start the execution of the deployment

      ![infra edit release](./assets/infra-edit-option.png)

      ![infra prerelease option](./assets/infra-prerelease-option.png)

   4. Approve the deployment to demo and/or staging, and then to production:
      1. Open the [Infrastructure Deploy Production Release](../.github/workflows/infra-deploy-release.yml) workflow run just started that has the name of the release you're just published above
      2. [Approve](https://docs.github.com/en/actions/managing-workflow-runs/reviewing-deployments) the environment(s) listed in the UI to allow the deployment to continue for each of those respective environments
         ![queued deployment](./assets/infra-release-queued.png)
         **IMPORTNT**: the option to deploy to staging and prod environments will be enabled only when the branch that triggered the initial workflow is a release branch (eg release/2022.01)
4. Every environment: Add pod identity
   1. Manually run the workflow [Infrastructure Add AKS Pod-identity](../.github/workflows/infra-add-aks-pod-identity.yml), selecting the name of the environment to deploy to (for example demo)
   2. For all environments except dev you will need to [approve deployment](https://docs.github.com/en/actions/managing-workflow-runs/reviewing-deployments)

### Deploying infra from CI/CD

1. Trigger build by _either_:
   * Touching any file in tools/infrastructure on the `master` branch (via a PR)
   * Manually running [Infrastructure CI/CD](../.github/workflows/infra-ci-cd.yml) workflow
   * Create a `release/*` branch (eg release/2022.01). Note: this is the only method to deploy to staging and prod environments as explained in [Branch and deployment strategy](branch-and-deployment-strategy.md)
2. Deploy to dev: [Infrastructure CI/CD](../.github/workflows/infra-ci-cd.yml) will trigger *automatically* to deploy infrastructure to dev environment (ie you don't need to do anything)
3. Deploy to qa: once deployed to the dev environment, the [Infrastructure CI/CD](../.github/workflows/infra-ci-cd.yml) workflow will queue up a deployment for the infrastructure to the qa environment.
   ![queued deployment](./assets/infra-ci-queued.png)
   This deployment will need to be reviewed then [approved in github](https://docs.github.com/en/actions/managing-workflow-runs/reviewing-deployments)
4. Deploy to demo, staging, prod-xxx environments:
   1. Go to the [Releases list](https://github.com/MRI-Software/web-api-startery/releases) in the github repo
   2. Find the pre-release that you want to deploy, it will start with 'infra-master-' or 'infra-release-'
      ![infra release](./assets/infra-release.png)
   3. To deploy the release, select the 'Edit' option, _**uncheck**_ 'Set as pre-release', and then select 'Update release'. This will start the execution of the deployment

      ![edit release](./assets/infra-edit-option.png)

      ![prerelease option](./assets/infra-prerelease-option.png)

   4. Approve the deployment to demo and/or staging, and then to production:
      1. Open the [Infrastructure Deploy Production Release](../.github/workflows/infra-deploy-release.yml) workflow run just started that has the name of the release you're just published above
      2. [Approve](https://docs.github.com/en/actions/managing-workflow-runs/reviewing-deployments) the environment(s) listed in the UI to allow the deployment to continue for each of those respective environments
         ![queued deployment](./assets/infra-release-queued.png)
         **IMPORTNT**: the option to deploy to staging and prod environments will be enabled only when the branch that triggered the initial workflow is a release branch (eg release/2022.01)


## Deploying app from CI/CD

> **TIP**: to discover the configuration values used during deployment run: `./tools/infrastructure/get-product-conventions.ps1`

1. Trigger build by _either_:
   * Touching any file in tools/infrastructure on the `master` branch (via a PR)
   * Manually running [Application CI/CD](../.github/workflows/app-ci-cd.yml) workflow
   * Create a `release/*` branch (eg release/2022.01). Note: this is the only method to deploy to staging and prod environments as explained in [Branch and deployment strategy](branch-and-deployment-strategy.md)
2. Deploy to dev: [Application CI/CD](../.github/workflows/app-ci-cd.yml) will trigger *automatically* to deploy app to dev environment (ie you don't need to do anything)
3. Deploy to qa: once deployed to the dev environment, the [Application CI/CD](../.github/workflows/app-ci-cd.yml) workflow will queue up a deployment for the app to the qa environment.
   ![queued deployment](./assets/app-ci-queued.png)
   This deployment will need to be reviewed then [approved in github](https://docs.github.com/en/actions/managing-workflow-runs/reviewing-deployments)
4. Deploy application to demo, staging, prod-xxx environments:
   1. Go to the [Releases list](https://github.com/MRI-Software/web-api-starter/releases) in the github repo
   2. Find the pre-release that you want to deploy, it will start with 'app-master-' or 'app-release-'
      ![app release](./assets/app-release.png)
   3. To deploy the release, select the 'Edit' option, **_uncheck_** 'Set as pre-release', and then select 'Update release'. This will start the execution of the deployment

      ![edit release](./assets/infra-edit-option.png)

      ![prerelease option](./assets/infra-prerelease-option.png)

   4. Approve the deployment to demo and/or staging, and then to production:
      1. Open the [Application Deploy Production Release](../.github/workflows/app-deploy-release.yml) workflow execution just started that has the name of the release you're just published above
      2. [Approve]((https://docs.github.com/en/actions/managing-workflow-runs/reviewing-deployments)) the environment(s) listed in the UI to allow the deployment to continue for each of those respective environments
         ![queued deployment](./assets/app-release-queued.png)
         **IMPORTNT**: the option to deploy to staging and prod environments will be enabled only when the branch that triggered the initial workflow is a release branch (eg release/2022.01)

## Granting access to Azure resources

### Steps

1. Decide on the access level for each person (see 'Access levels' section below)
2. Open the github workflow [Infrastructure Grant Azure Environment Access](../.github/workflows/infra-grant-azure-env-access.yml)
3. Select the "Run workflow" button
   ![run workflow](./assets/infra-grant-access-run-workflow.png)
4. In the dialog:
   1. Select the Environment to which to grant access (select 'all' to expedite the process considerably)
   2. Select the Access level that is appropriate for the person (see below for description of each access level)
   3. In 'A comma delimited list of User principal names to grant' add the email address of the person(s) to grant access
   4. Select 'Run workflow' button
5. For all environments except dev, the workflow run will need to be reviewed then [approved in github](https://docs.github.com/en/actions/managing-workflow-runs/reviewing-deployments)
   * See example workflow run screenshots below
   * Those members of the [Web API Starter - Production approver](https://github.com/orgs/MRI-Software/teams/web-api-starter-production-approver/members) will be able to approve

Once approved, the Azure RBAC permissions applicable to the selections above will be provisioned to the resources in Azure.

To check existing access, go to the Azure AD group in the portal. The naming convention of these groups is as follows:

* development team: sg.role.development.webapistarter._\[env]_. EG:
  * dev environment: [sg.role.development.webapistarter.dev](https://portal.azure.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Overview/groupId/27054828-d480-4702-aaa3-fe906caed400)
* GPS: sg.role.supporttier1.webapistarter._\[env]_.
* App Admin: sg.role.supporttier2.webapistarter._\[env]_.

_Example workflow run:_
![run workflow](./assets/infra-grant-access-run-workflow-run-1.png)

![run workflow](./assets/infra-grant-access-run-workflow-run-2.png)

### Revoking access to Azure resources

1. Open the github workflow [Infrastructure Revert Azure Environment Access](../.github/workflows/infra-revert-azure-env-access.yml)
2. Select the "Run workflow" button\
   ![run workflow](./assets/infra-revoke-access-run-workflow.png)
3. In the dialog:
   1. Select the Environment to which to revoke access
   2. Select the Access level that's to be revoked for the person
   3. In 'User to revoke' add the email address of the person to revoke access
   4. Select 'Run workflow' button
4. For all environments except dev, the workflow run will need to be reviewed then [approved in github](https://docs.github.com/en/actions/managing-workflow-runs/reviewing-deployments)

### Azure environment Access levels

1. development
   * dev, qa: 
     * admin access to Azure SQL db
     * contributor access to Azure resources (_including_ access to keyvault)
   * demo:
      * data read/write access to AIG Azure SQL db
      * contributor access to Azure resources (no access to keyvault)
   * staging and prod: 
     * data read access to Azure SQL db
     * read access to Azure resources (no access to keyvault)
2. GPS / support-tier-1
   * demo, staging and prod environments: 
     * data read access to Azure SQL db
     * read access to Azure (no access to keyvault)
3. App Admin / support-tier-2
   * demo, staging and prod environments:
      * contributor access to Azure SQL db
      * contributor access to Azure (_including_ access to keyvault)

To provide a comprehensive list of permissions per environment execute [print-product-convention-table.ps1](../tools/infrastructure/print-product-convention-table.ps1),
specifically, the example with the description "Returns tables describing all Azure RBAC and Azure ADD security group membership"

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
      # IMPORTANT: You will likely need to connected to the office VPN in order to satisfy the firewall rules configured in the Azure SQL db
      # 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
      ./tools/dev-scripts/deploy.ps1 -InfA Continue -Login -Subscription xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
      ````
7. Test that it worked:
    * browse to the "Api health Url" printed to the console
    * Import the postman [collection](../tests/postman/api.postman_collection.json) and [environment](../tests/postman/api-local.postman_environment.json),
      change the baseUrl postman variable to the "Api Url" printed to the console. Run the requests in the collection


## Cleanup

To remove all Azure resources and AKS pod identity run the deprovision-azure-resources.ps1 script from a powershell prompt (assuming you have permissions),
or running the github workflow [Infrastructure Uninstall](../.github/workflows/infra-uninstall.yml)

### From a powershell prompt

```pwsh
# 'CC - Visual Studio Enterprise' subscription id: 402f88b4-9dd2-49e3-9989-96c788e93372
./tools/infrastructure/deprovision-azure-resources.ps1 -InfA Continue -Environment xxx -UninstallAksApp -DeleteAADGroups -Login -Subscription xxxxxxxx-xxxx-xxxxxxxxx-xxxxxxxxxxxx
```

### From the github workflow

1. Go to the Actions tab in the github repo
2. Manually run the workflow 'Infrastructure Uninstall', selecting the name of the environment to uninstall from


## Troubleshooting `provision-azure-resources.ps1`

When running `provision-azure-resources.ps1`, you might receive an error with the following message:

```cmd
Login failed for user '<token-identified principal>'
```

To resolve the problem try re-running the provisioning script again (it's safe to do so). This still may not work if the script
is provisioning a secondary Azure SQL server as part of a failover group. In this case, try waiting for somewhere between 15-60 minutes and re-run the script.
It appears that the creation of the replicated database takes sometime and is cause of the problem.