# Add a new environment

<!-- TOC -->
* [Add a new environment](#add-a-new-environment)
  * [1. Create github environment](#1-create-github-environment)
  * [2. Authenticate github actions with Azure](#2-authenticate-github-actions-with-azure)
  * [3. Initial setup of deployment scripts and github workflows](#3-initial-setup-of-deployment-scripts-and-github-workflows)
  * [4. Configure DNS and TLS](#4-configure-dns-and-tls)
  * [5. Configure okta](#5-configure-okta)
  * [6. Deploy infrastructure](#6-deploy-infrastructure)
  * [7. Deploy application code](#7-deploy-application-code)
  * [8. Test the application](#8-test-the-application)
<!-- TOC -->

> [!IMPORTANT]
> If you are adding a new production environment, then you will need to make sure that you are making adjustments
> to script and github workflow files in a release branch

## 1. Create github environment

1. Create github environment:

   1. Add the new environment to [github-setup-environments.yml](../.github/workflows/github-setup-environments.yml)
   2. Go to the Actions tab in the github repo
   3. Manually run the workflow you have adjusted above: [Github Create Environments](https://github.com/christianacca/web-api-starter/actions/workflows/github-setup-environments.yml)

2. Add approvals and branch protection policies to github environment

   Go to [Settings > Environments](https://github.com/christianacca/web-api-starter/settings/environments) in the github repo 
   and select the environment you have just created. Add the branch protection rules as required for the new environment.

   Recommendations:
   * qa: require approval (to allow qa to pull changes into environment at their own pace, and to avoid a deploy from release branch being overwritten)
   * demo, demo-xx: require approval
   * staging, prod, and prod-xx:
      * require approval
      * only allowed to run for release branches and the default (eg master) branch

   For more information see: <https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment>

## 2. Authenticate github actions with Azure

1. Ensure service principal used by github actions can authenticate for the new environment.

   The github actions workflow will authenticate to Azure AD using a service principal using a federated credential for the
   environment it is attempting to deploy to. Therefore, for any new environment, you need to ensure that the service principal
   has a federated credential setup for this new environment.

   If the new environment is in a difference subscription from the existing environments, then you will need to:
   1. Create a new service principal. Follow the section "Create automation service principals" as described in the repo
      [service-principal-automate](https://github.com/MRI-Software/service-principal-automate/tree/main?tab=readme-ov-file#create-automation-service-principals)
   2. Modify [set-azure-connection-variables.ps1](../.github/actions/azure-login/set-azure-connection-variables.ps1) 
      with the details of the new subscription and service principal client id and principal id
   3. [Deploy shared services](./deploy-app.md#deploy-shared-services) to ensure the new service principal is assigned the required permissions
 
   For new or exiting service principals, you will need to create a federated credential for the new environment for the
   service principal that will deploy to the new environment.

   Follow the section "Create github federated credentials" as described in the repo [service-principal-automate](https://github.com/MRI-Software/service-principal-automate/tree/main?tab=readme-ov-file#create-github-federated-credentials),
   making sure to include just the environment you are adding in the list of environments the script will then add a federated credential for.

2. Adjust azure connection variables

   Review and adjust the list of environments in [set-azure-connection-variables.ps1](../.github/actions/azure-login/set-azure-connection-variables.ps1) 
   to include the new environment. This will be used for authentication to Azure AD, and knowing the id of azure subscription
   for the new environment.

## 3. Initial setup of deployment scripts and github workflows

1. Adjust the list of environments supported by infra-as-code deployment scripts

   Add the new environment to [get-product-environment-names.ps1](../tools/infrastructure/get-product-environment-names.ps1)

2. Modify the github workflow that deploys infrastructure

   You will need to add a new [github actions job](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/using-jobs-in-a-workflow) for the new environment.

   If the new environment is:
   * a dev/test environment, you will need to modify [Infrastructure CI/CD](../.github/workflows/infra-ci-cd.yml)
   * a production environment, you will need to modify [Infrastructure Deploy Production Release](../.github/workflows/infra-deploy-release.yml)

3. Modify the github workflow that deploys application code

   You will need to add a new [github actions job](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/using-jobs-in-a-workflow) for the new environment.

   If the new environment is:
   * a dev/test environment, you will need to modify [Application CI/CD](../.github/workflows/app-ci-cd.yml)
   * a production environment, you will need to modify [Application Deploy Production Release](../.github/workflows/app-deploy-release.yml)

   Also, modify [__Application Deployment](../.github/workflows/__app-deploy.yml):
   * to include the new environment in the github actions step `Map variables`.
   
   **Note**: not all configuration variables will be known at this stage, in which case add dummy placeholder values 
   that you will then assign in the steps below.

4. Modify the github workflows that perform other tasks like granting azure access

   Look for the github workflow files that accept an environment as input parameter. Adjust this list to include the new environment.
   Some of the github workflows that you have adjusted might also need a new job adding for the new environment, some might not.

## 4. Configure DNS and TLS

> [!TIP]
> You can defer the DNS and TLS configuration until after the application code has been deployed to the new environment.
> To do this you will need to adjust the [get-product-conventions.ps1](../tools/infrastructure/get-product-conventions.ps1),
> setting `IsCustomDomainEnabled` to `$false` for the new environment.
> The applications will still be available to access over https using the default host names provided by the Azure
> Container Apps service. However, the applications will not be accessible using the custom host names until the DNS
> and TLS configuration has been completed.

> [!TIP]
> The DNS records and WAF rules _can_ be registered even before the workload services are deployed to the new environment

1. Register DNS records for the workload services that will be deployed to the new environment

   1. Follow the guidance [Register DNS records](./deploy-app.md#register-dns-records) to list the DNS records that need to
      be registered at the appropriate DNS zone
   2. Add the DNS records to the DNS zone for the new environment

2. Add whitelists to Cloudflare Web Application Firewall (WAF)
    
   1. Follow the guidance [Add whitelists to Cloudflare Web Application Firewall (WAF)](./deploy-app.md#add-whitelists-to-cloudflare-web-application-firewall-waf)
      to list the WAF rules that need to be registered at the appropriate WAF
   2. Add the WAF rules to the WAF for the new environment

3. Review Cloudflare origin certs

   Cloudflare origin certs are used for secure communication between the cloudflare proxy and the workload services
   such as Azure Container Apps. These cloudflare origin certs typically will have been created as wildcard certs.
   As such a new subdomain for each workload service that will be deployed to the new environment should be covered by
   the existing wildcard cert.

   This should be confirmed by finding the details of the existing origin cert to check that the new host names are covered.
   For example:

   ![cloudflare origin cert](./assets/add-environment-cloudflare-origin-cert.png)

   If the existing origin cert does not cover the new subdomain, then you will need to create a new origin cert for the
   new hostname as explained in the section [Add TLS certificates to shared key vault](./deploy-app.md#add-tls-certificates-to-shared-key-vault)

## 5. Configure okta

1. Configure okta (identity and token provider) for new environment

   As required, ensure the following okta configurations are created for the new environment:
   * Okta Authorization server with the same policies as the existing environments
   * Okta Application for each workload service that needs to acquire identity and/or access tokens

   Once created you will add in the following steps:
   * the client id and authorization server url as config values
   * the client secret as a keyvault secret

2. Set okta variables in the app deployment github workflow

   Now that the okta configuration has been created, set the okta variables in [__Application Deployment](../.github/workflows/__app-deploy.yml)  
   github workflow. For example, change the `Map variables` step to include the following variables:
   * `Api_TokenProvider_Authority` - the new okta authorization server url

## 6. Deploy infrastructure

> [!IMPORTANT]
> It might take several attempts to run the infrastructure github workflow for the new environment. That's ok, the
> infra-as-code deployment is idempotent, so if you run the workflow, and it fails, you can run it again, and it will 
> only deploy the changes that are required.

1. Deploy the infrastructure to the new environment

   Follow the guidance [Deploying infrastructure from CI/CD](./deploy-app.md#deploying-infrastructure-from-cicd) to deploy the infrastructure for the new environment

   If you do need to run the workflow multiple times, you will need to:
   * Cancel the workflow run (yes, this is counterintuitive)
   * Click on the "Re-run failed jobs" button in the workflow
   * Approve the deployment to the new environment to kick off the deployment again

2. Grant initial access to Azure environment

   To grant access to the new environment in Azure, follow the guidance [Granting access to Azure or Power-BI resources](./deploy-app.md#granting-access-to-azure-or-power-bi-resources)

   You will need to grant yourself or someone who is responsible for assisting with the deployment, access to the new
   environment in Azure.

   That person will need to be able to add keyvault secrets which is the highest access rights available that can be
   granted to a user for the new environment.
   As described in the section [Azure environment Access levels](./deploy-app.md#azure-environment-access-levels):
   * development team role (aka PD) has access to the keyvault deployed to dev/test environments
   * support-tier2 team role will have access to the keyvault deployed to all other environments

   To revoke access granted above, for example where access was granted to a developer to assist with the deployment,
   follow the guidance [Revoking access to Azure resources](./deploy-app.md#revoking-access-to-azure-resources)

## 7. Deploy application code

> [!IMPORTANT]
> It will likely take 30 mins or so for permissions granted in previous steps above to take effect. You will
> not be able to access the keyvault nor other Azure resources in the new environment until the permissions have taken effect.

1. Add any keyvault secrets for the new environment

   The infrastructure deployment will have created a new keyvault for the new environment. 
   Review the existing secrets in use for the existing environments, and ensure that secret keys are added to the new 
   keyvault as required.

   To find the names of the keyvaults in azure, you can use the following command:

   ```pwsh
   ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Keyvault } -AsArray | Select Env, ResourceName
   ```
   
2. Add a "SentinelKey" key value to the Azure app configuration service that is used by one or more workload services

   A sentinel key is a key that is used to trigger a refresh of the configuration values in the Azure app configuration service.
   This step is only required if you are using the Azure app configuration service to store configuration keys for the workload services.

   1. Find the store that the new environment will use (see [Store used for an environment](configs-and-feature-flags.md#store-used-for-an-environment))
   2. Follow the guidance in [Adding, deleting, or modifying configuration keys](configs-and-feature-flags.md#adding-deleting-or-modifying-configuration-keys)
      to add a new value to the key named "SentinelKey" in the Azure app configuration service that workload services use to get their configuration values.
      Make sure to label the new value with the name of the new environment.

3. Deploy the application to the new environment

   Follow the guidance [Deploying app from CI/CD](./deploy-app.md#deploying-app-from-cicd) to deploy the application code for the new environment

## 8. Test the application

1. Add postman environment file for the new environment

   The postman environment files to create are in the folder [postman](../tests/postman).

   Create for the following postman environment files:
   * api-{newenv}.postman_environment.json. Used for the [api.postman_collection.json](../tests/postman/api.postman_collection.json)

2. Test the application in the new environment

   To find the host names of the workload services, run the following command:

   ```pwsh
   ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Values } -AsArray | 
     ? { $_.Type -in 'AksPod', 'AcaApp' } | Select Env, Name, HostName
   ```

   Test the workloads using the following postman collections:
   * [api.postman_collection.json](../tests/postman/api.postman_collection.json)

