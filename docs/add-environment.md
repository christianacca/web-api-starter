# Add a new environment

> [!IMPORTANT]
> If you are adding a new production environment, then you will need to make sure that you are making adjustments
> to script and github workflow files in a release branch

1. Create github environment:

   1. Add the new environment to [github-setup-environments.yml](../.github/workflows/github-setup-environments.yml)
   2. Go to the Actions tab in the github repo
   3. Manually run the workflow you have adjusted above: [Github create environments](https://github.com/christianacca/web-api-starter/actions/workflows/github-setup-environments.yml)

2. Add approvals and branch protection policies to github environment

   See: <https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment>

   Recommendations:
   * qa: require approval (to allow qa to pull changes into environment at their own pace, and to avoid a deploy from release branch being overwritten)
   * demo, demo-xx: require approval
   * staging, prod, and prod-xx:
      * require approval
      * only allowed to run for release branches and the default (eg master) branch

3. Ensure existing service principal used by github actions can authenticate for the new environment.

   The github actions workflow will authenticate to Azure AD using a service principal using a federated credential for the
   environment it is attempting to deploy to. Therefore, for any new environment, you need to ensure that the service principal
   has a federated credential setup for this new environment.

   Follow the section "Create github federated credentials" as described in the repo [service-principal-automate](https://github.com/MRI-Software/service-principal-automate/tree/main?tab=readme-ov-file#create-github-federated-credentials),
   making sure to include just the environment you are adding in the list of environments the script will then add a federated credential for.

4. Adjust azure connection variables

   Review and adjust the list of environments in [set-azure-connection-variables.ps1](../.github/actions/azure-login/set-azure-connection-variables.ps1) 
   to include the new environment. This will be used for authentication to Azure AD, and knowing the id of azure subscription
   for the new environment.

5. Adjust the list of environments supported by infra-as-code deployment scripts

   Add the new environment to [get-product-environment-names.ps1](../tools/infrastructure/get-product-environment-names.ps1)

