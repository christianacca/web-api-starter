# Create initial github environments

1. Create Azure AD app registrations to allow github actions to authenticate to Azure AD.

   Run the two scripts as described in this repo [service-principal-automate](https://github.com/MRI-Software/service-principal-automate)

2. Create github environments:

   1. (optional) Adjust the environments setup in [github-setup-environments.yml](../.github/workflows/github-setup-environments.yml)
   2. Go to the Actions tab in the github repo
   3. Manually run the workflow 'Github Create Environments'

3. Add approvals and branch protection policies

   Go to [Settings > Environments](https://github.com/christianacca/web-api-starter/settings/environments) in the github repo
   and select the environments you have just created. Add the branch protection rules as required to each environment.

   Recommendations:
   * qa: require approval (to allow qa to pull changes into environment at their own pace, and to avoid a deploy from release branch being overwritten)
   * demo, demo-xx: require approval
   * staging, prod, and prod-xx:
     * require approval
     * only allowed to run for release branches and the default (eg master) branch

   For more information see: <https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment>

4. Create a convenience azure-login github action

   For any action in the github workflow to be able to perform any operation against Azure, the github workflow must sign-in to azure first.
   Create a custom github action like you see in this repo: [azure-login](../.github/actions/azure-login)