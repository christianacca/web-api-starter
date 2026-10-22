# Move Function Apps to Flex Consumption and deploy with Azure/functions-action

- Status: accepted
- Deciders: Sumedh Bhat
- Date: 2026-10-21

Technical Story: deployments of the managed-identity Y1 setup ([ADR 0002](0002-remain-on-y1-consumption-plan-rather-than-flex.md)) failed intermittently in `data-services-gateway` (DSG) and had to be rerun up to 10 times.

Evidence: [`evidence/0003-flex-consumption-deployment-reliability/README.md`](./evidence/0003-flex-consumption-deployment-reliability/README.md)

## Context and Problem Statement

ADR 0002 kept the Function Apps on Windows Y1 Consumption after removing shared keys. That meant no Azure Files content share, a package served from a private blob through `WEBSITE_RUN_FROM_PACKAGE`, and a custom GitHub action (`azure-function-packages`). The action uploaded the zip, ran `az functionapp restart`, then called `syncfunctiontriggers`.

In DSG that last call failed intermittently with `Encountered an error (ServiceUnavailable) from host runtime`. One production release needed 11 attempts.

We wanted to know why, and whether Flex Consumption with Microsoft's `Azure/functions-action` avoids it while keeping identity-only storage access.

## What caused the failures

The custom action, not the hosting plan, and not executions running during the deployment.

`az functionapp restart` returns before the Functions host has restarted. The action called `syncfunctiontriggers` straight after, so the call sometimes reached the app while the old host was stopping or the new one hadn't started yet. The host answers 503 in that window. This reproduced in this repo's dev environment with the same error (2 of 13 restarts). Host logs put the failed sync 2 seconds before `Job host stopped` and 20 seconds before `Host started`. With no restart, sync never failed, including under load. Load made no difference either way.

Any deployment that restarts a Y1 app and then syncs triggers itself has this race. A retry loop, as DSG added, makes failures less likely. It doesn't remove the race, and it leaves restart and sync as our code to maintain.

## Decision Drivers

- Deployments must succeed first time without retry loops in our own scripts.
- No shared keys or connection strings for host storage or deployment.
- Use Microsoft's supported deployment path instead of a custom one.
- Low running cost for low-volume apps.

## Considered Options

- **Option 1.** Stay on Y1 and fix the custom action: retry the sync, or poll the host until it is running.
- **Option 2.** Stay on Y1 and go back to `Azure/functions-action`.
- **Option 3.** Move to Flex Consumption and deploy with `Azure/functions-action` (One Deploy).

## Decision Outcome

Chosen option: Option 3.

On Flex the action uses One Deploy. The platform writes the package to a blob container using the app's user-assigned identity, then restarts the app and syncs triggers itself. Our pipeline makes no restart or sync calls, so the race is gone. Deploying in dev 10 times (5 of them under continuous queue load) gave no platform failures. All functions were registered every time, and all 5,090 messages sent during the busy deployments were processed on their first delivery.

Option 2 isn't possible with identity-only storage. The Y1 path the action uses on Windows needs either the Azure Files content share (shared key) or `WEBSITE_RUN_FROM_PACKAGE` with a URL. With a URL, a deploying tool has to upload the blob and sync triggers itself, which is the custom action again. Option 1 keeps the problem in our code.

### What changed

- `internal-api.bicep` creates a Linux `FC1` plan and a `functionapp,linux` site with `functionAppConfig`. The deployment container (`app-package`) uses `UserAssignedIdentity` authentication, the runtime is `dotnet-isolated` 10.0, and `instanceMemoryMB` and `maximumInstanceCount` are parameters (512 and 100 by default).
- `FUNCTIONS_EXTENSION_VERSION`, `FUNCTIONS_WORKER_RUNTIME`, `WEBSITE_RUN_FROM_PACKAGE*`, `WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED`, `netFrameworkVersion`, `use32BitWorkerProcess` and `ftpsState` are removed. Flex doesn't allow them.
- Host storage still uses `AzureWebJobsStorage__credential: managedidentity` with the user-assigned identity, and the storage account still has `allowSharedKeyAccess: false`.
- `.github/actions/azure-function-packages` is deleted. `__app-deploy.yml` uses `Azure/functions-action@v1` with the existing OIDC login.
- The GitHub deployment principal loses `Storage Blob Data Contributor` on the Functions storage account. It only had it to upload the package. Removing it from bicep doesn't delete the existing assignment in already provisioned environments.
- `provision-azure-resources.ps1` moves apps onto Flex before the ARM deployment. Azure can't move an app onto Flex in place, so it has to be deleted and re-created under the same name. `Get-NonFlexFunctionApp` finds apps that exist and aren't on Flex. If there are any, the script checks Flex is available in the region and runs `az deployment group validate` on the full deployment. Only then does `Remove-NonFlexFunctionApp` delete the app, and its plan if that is left empty. Validation catches template, parameter, policy and permission errors while the old app still exists. It can't catch everything (regional capacity, for example). If the create still fails, re-running the script skips the delete and retries the create. Running master's pipelines instead re-creates the Y1 app. Nothing changes on later runs, and `-WhatIfAzureResourceDeployment` only reports.

### Positive Consequences

- The cause of the intermittent failures is removed, not retried around.
- Less of our own deployment code. Restart and sync belong to the platform.
- Scale-out no longer depends on the Azure Files share that ADR 0002 had to give up. Flex has per-function scaling up to 1,000 instances.
- Identity-only storage is the normal Flex setup, not a workaround.
- VNet integration and always-ready instances are available if needed later.

### Negative Consequences

- Each environment's Function App is deleted and re-created on its first infra deployment after this change. The app is unavailable until the following app deployment publishes code. Deploy infra and app together, and expect a short outage.
- Cost goes up. DSG's ADR 0004 projects $6 to $46 a month at 2,048 MB across its 14 prod-like apps, against about $1 on Y1. At 512 MB the projection is about a quarter of that.
- Instance memory has to be chosen per app. See the evidence README. 512 MB worked for this template; DSG's `deploypbi` should start at 2,048 MB.
- Linux only, one app per plan, and no deployment slots.
- With the default `Recreate` update strategy, a deployment terminates executions that are running at the time, as the Y1 restart did. Queue messages are redelivered and Durable orchestrations replay, but long-running activities restart from the beginning.

## Site update strategy

The template uses Flex's default, `Recreate`. Switching to `RollingUpdate` is one line in `functionAppConfig` (`siteUpdateStrategy: { type: 'RollingUpdate' }`), or `az functionapp update-strategy config set --type RollingUpdate`. The Bicep types for the API version the AVM site module uses don't include the property yet, so adding it gives a Bicep warning (BCP037). The deployed dev app does report `siteUpdateStrategy: Recreate` in `functionAppConfig`, but setting it through this template hasn't been tested. The config change is easy. The rest takes more thought:

- Rolling updates are in public preview.
- Old and new code run side by side during a deployment. Durable orchestrations need an explicit [orchestration version match strategy](https://learn.microsoft.com/azure/durable-task/common/durable-orchestration-versioning), and queue message and table schemas must stay backward compatible.
- In return, in-flight executions finish (up to 60 minutes) instead of being terminated.

## Links

- Supersedes [ADR 0002](0002-remain-on-y1-consumption-plan-rather-than-flex.md)
- Evidence: [`evidence/0003-flex-consumption-deployment-reliability/README.md`](./evidence/0003-flex-consumption-deployment-reliability/README.md)
- Flex Consumption plan: <https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan>
- Site update strategies: <https://learn.microsoft.com/azure/azure-functions/flex-consumption-site-updates>
- Flex Consumption app setting deprecations: <https://learn.microsoft.com/azure/azure-functions/functions-app-settings#flex-consumption-plan-deprecations>
- Azure/functions-action: <https://github.com/Azure/functions-action>

<!-- markdownlint-disable-file MD013 -->
