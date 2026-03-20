# GitHub Workflow Direct Callback Migration Plan

## Purpose

Replace GitHub `workflow_run` webhook delivery with direct, Entra-authenticated HTTP callbacks from GitHub Actions to the Internal API Function App.

The migration must be executed in verifiable phases. Each phase should end with:

1. a working system state for that phase,
2. explicit verification, preferably automated,
3. checklist updates for completed steps, and
4. feed-forward updates to future phases based on what was learned.

## Target Architecture

The steady-state design is:

1. The Functions app dispatches a GitHub workflow.
2. The workflow authenticates to Azure using the existing GitHub OIDC plus Entra service principal pattern.
3. The workflow calls a dedicated Functions HTTP endpoint directly.
4. The Functions endpoint raises the same Durable external events currently used by the orchestrator.
5. The API project no longer receives GitHub webhooks for workflow completion.
6. The repo no longer depends on GitHub App webhook configuration or webhook secrets.

## Decisions Already Made

1. Preserve both orchestration signals.
   The workflow will send:
   - an `in progress` callback carrying the `runId`
   - a `completed` callback carrying final outcome data
2. Remove GitHub App webhook dependency entirely.
3. Update support-ticket generation to request a GitHub App for Actions permissions only.
4. Prefer a route name that does not retain `webhook` terminology.
5. Avoid dual delivery competition within an environment.
   For any environment being migrated, webhook-driven orchestration events and direct-callback-driven orchestration events must not both be active at the same time.
6. Preferred cutover strategy: disable webhook delivery at the source.
   For each environment, the preferred approach is to disable GitHub App webhook delivery before enabling direct callbacks in that environment. Code-based suppression is a fallback option only if GitHub-side reconfiguration cannot be completed safely in time.

## Execution Rules For The Coding Agent

1. Do not start a later phase until the current phase has been verified.
2. Keep changes focused to the current phase unless a blocker forces a small cross-phase edit.
3. The final step of every phase is mandatory:
   - update that phase checklist
   - add findings to the `Feed Forward` subsection of later phases
4. If verification fails, fix the phase before moving on.
5. Preserve existing behavior unless the phase explicitly changes it.
6. Prefer automated verification using build tasks, targeted searches, and reproducible commands.
7. Treat per-environment cutover as a control point.
   Before enabling direct callbacks for a given environment, disable or suppress webhook-based event raising for that same environment so both channels cannot compete.
8. Prefer source-side elimination over application-side suppression.
   If webhook delivery can be disabled in GitHub for an environment, do that instead of adding temporary code to ignore duplicate deliveries.

## Global Verification Commands

Use these where relevant at the end of each phase:

1. Build the full solution with the `build solution` task.
2. Build the API project with the `build api` task.
3. Build the Functions project with the `build functions` task.
4. Search for obsolete webhook references with repo-wide text search for:
   - `WebhookSecret`
   - `MapGitHubWebhooks`
   - `Octokit.Webhooks`
   - `api/github/webhooks`
   - `workflow_run`
5. For infrastructure phases, inspect Bicep diffs and validate referenced principal ids and audiences.
6. For documentation phases, search for stale webhook guidance in `docs/` and `tools/infrastructure/`.

## Baseline Benchmark Requirement

Before any migration code changes begin, establish and record a known-good baseline of the current webhook-based solution running locally. This baseline becomes the comparison point for the later phases.

The benchmark should capture:

1. the current local startup flow for API and Functions,
2. the current durable orchestration behavior,
3. the current webhook-driven event progression,
4. the monitoring or inspection method used to observe orchestration state, and
5. any local prerequisites or quirks needed to reproduce the current design successfully.

## Agent-Verifiable Local Observation Strategy

The coding agent should not rely on the Durable Functions Monitor UI as the primary verification mechanism.

For local verification against Azurite, prefer this order:

1. Start Azurite locally and confirm the storage emulator is reachable using the `AzureWebJobsStorage` connection string from the Functions local settings.
2. Start the local Functions host and capture host logs.
3. Trigger the orchestration and capture the returned `instanceId` from the HTTP response.
4. Use Functions host logs as the first-line signal to confirm:
   - orchestration scheduled
   - workflow dispatch attempted
   - webhook callback received
   - external events raised
   - orchestration completed or timed out as expected
5. Inspect the Azurite-backed Durable state for that `instanceId` as the durable-state source of truth. This can be done by using a script or code snippet to read the Durable Task Azure Storage tables and, where helpful, queues/blobs associated with the local task hub.
6. Use the Durable Functions Monitor extension only as an optional human-friendly secondary view.

This approach is preferred because the agent can automate it using local processes, captured logs, and direct inspection of emulator-backed state.

## Phase Checklist Legend

- `[ ]` not started
- `[x]` completed
- `Blocked:` follow-up required before phase can close

---

## Phase 0: Establish The Current-System Benchmark

### Goal

Run the solution locally in its current webhook-based form and verify that it behaves as designed before any migration work starts. This creates a benchmark for later comparison and reduces the risk of debugging pre-existing issues mid-migration.

### Steps

- [x] Review the existing local setup guidance and confirm all prerequisites for running the current API and Functions solution are satisfied on this machine.
- [x] Build the current solution without migration changes.
- [x] Start the current API locally.
- [x] Start the current Functions app locally, including any required dependencies such as Azurite.
- [x] Trigger the existing workflow-orchestration flow using the current supported path.
- [x] Capture the orchestration `instanceId` returned by the current workflow start path.
- [x] Observe orchestration progress using agent-verifiable methods. Preferred order:
   - Functions host logs and Durable runtime logs
   - direct inspection of Azurite-backed Durable state for the captured `instanceId`
   - any existing repo scripts that help confirm local host behavior
   - Durable Functions Monitor only as an optional secondary visual check
- [x] Confirm the current design behaves as expected end to end:
   - workflow dispatch occurs
   - webhook callback path is exercised
   - orchestration receives the expected external events
   - orchestration reaches the expected terminal state
- [x] Record the benchmark evidence in this document’s execution log format, including:
   - commands used
   - functions host log evidence
   - how Durable state was inspected in Azurite
   - the observed orchestration state transitions for the captured `instanceId`
   - any environment-specific local setup notes
- [x] If baseline issues are found, stop migration work and either fix them first or document them explicitly as pre-existing constraints.
- [x] Update the checklist for this phase.
- [x] Feed forward any setup, observability, or reproducibility findings into Phases 1 through 7.

### Verification

1. `build solution` succeeds on the unmodified codebase.
2. The current API and Functions apps start locally.
3. A real orchestration run is observed locally and reaches the expected state.
4. The current webhook-based event flow is confirmed with Functions host logs.
5. Durable state for the captured `instanceId` is confirmed against Azurite-backed storage using a reproducible inspection method.
6. A reproducible benchmark record exists for later comparison.

### Feed Forward

- Local verification can use Azurite-backed Durable tables directly. `az storage table list` and `az storage entity query` work against the checked-in `AzureWebJobsStorage` connection string when `AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1` is set for the self-signed Azurite HTTPS endpoints.
- The local task hub is `TestHubName`, with durable state recorded in `TestHubNameInstances` and `TestHubNameHistory`.
- The original local benchmark blocker was a mismatched GitHub App configuration. The Key Vault private key currently loaded locally matches GitHub App `2800136` / installation `108147932`, not the previously configured local values `2800205` / `108147870`.
- Any future local benchmark that needs the API start path must include an explicit bearer-token acquisition step or a documented local auth bypass, because the proxied `POST /api/workflow/start` route is not anonymously callable.
- Dispatch success alone is not sufficient benchmark evidence. For local verification of the legacy webhook design, also prove where the active GitHub App webhook is pointed and whether a tunnel or override is routing callbacks back to the local API.
- A reproducible local webhook benchmark is now possible by hosting the API on `https://localhost:5000`, exposing it through a developer-owned persistent dev tunnel, and pointing the `Web Api Starter (Local)` GitHub App webhook URL at `<tunnel-url>/api/github/webhooks` with anonymous tunnel access enabled for port `5000`.
- During the successful local benchmark, GitHub delivered one unrelated `workflow_run` webhook for `Orchestrator Test Workflow` that the API logged as unsupported before delivering the expected `WorkflowInProgress` and `WorkflowCompleted` events for the target orchestration instance.

### Phase 0 Execution Log

- Date: 2026-03-18
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Reviewed the local setup and orchestration docs, built the unmodified solution, started Azurite, started the API, started the Functions host, verified local health endpoints, triggered one diagnostic orchestration directly against the Functions host, and captured host-log plus durable-table evidence for the resulting instance failure.
- Verification run: `build solution`; `dotnet run --project ./src/Template.Api`; `func start` from `src/Template.Functions/bin/Debug/net10.0`; `curl -sk https://localhost:5000/health`; `curl http://localhost:7071/api/Echo`; `curl -sk -X POST https://localhost:5000/api/workflow/start ...` returned `401`; `curl -X POST http://localhost:7071/api/workflow/start -H 'Content-Type: application/json' -d '{"WorkflowFile":"webhook-integration-test.yml","RerunEntireWorkflow":true}'` returned `{"id":"7e3444002d5f4d61b409518b6c631477"}`; `AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1 az storage table list --connection-string <AzureWebJobsStorage>` returned `TestHubNameHistory`, `TestHubNameInstances`, `TestHubNamePartitions`; `AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1 az storage entity query --table-name TestHubNameInstances ...` showed `RuntimeStatus=Failed` for instance `7e3444002d5f4d61b409518b6c631477`; `AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1 az storage entity query --table-name TestHubNameHistory --filter "PartitionKey eq '7e3444002d5f4d61b409518b6c631477'" ...` showed `ExecutionStarted`, `TaskScheduled`, `TaskFailed`, and `ExecutionCompleted` events.
- Files changed: `docs/github-workflow-direct-callback-migration-plan.md`
- Findings: The current codebase builds cleanly and both local hosts can start. The local API health endpoint and local Functions echo endpoint both respond `200`. The proxied API workflow-start path requires bearer auth and returned `401 Unauthorized` in this session. A direct diagnostic trigger against the anonymous Functions route created a durable instance but failed immediately in `TriggerWorkflowActivity` because the GitHub App JWT/private key material is invalid, producing `Octokit.AuthorizationException: A JSON web token could not be decoded`. Durable state in Azurite confirms the failure and shows that no webhook wait state was reached.
- Feed-forward updates applied to later phases: Added Phase 0 feed-forward notes on the Azurite inspection method, the local task hub/table names, the need to fix GitHub App private key material before relying on baseline comparisons, and the need to account for API auth in any future local benchmark.
- Remaining risks: Phase 0 is not closed. No real GitHub Actions run was dispatched, no webhook callback reached the local stack, and the current webhook-based orchestration path has not been verified end to end on this machine.

- Date: 2026-03-19
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Isolated the original dispatch failure to a mismatched local GitHub App configuration, updated the local API and Functions development settings to use the GitHub App and installation that match the Key Vault private key, removed the API Key Vault disable override, verified both hosts can now load GitHub secrets from Key Vault, retried the supported proxied API workflow-start path with a valid bearer token, and correlated the resulting orchestration instance to a real successful GitHub Actions run.
- Verification run: `dotnet build src/Template.Functions/Template.Functions.csproj`; repo-local diagnostic `tmp/ghdiag` confirmed both Functions and API config paths can authenticate to GitHub using App `2800136` and installation `108147932`; `curl -sk -X POST https://localhost:5000/api/workflow/start -H 'Authorization: Bearer <token>' -H 'Content-Type: application/json' -d '{"WorkflowFile":"webhook-integration-test.yml","ReRunEntireWorkflow":true}'` returned `{"id":"f97caa2686f14751b3b9b29d7e85a048"}`; Functions host logs showed `TriggerWorkflowActivity` completed successfully for that instance; `tmp/ghdiag --instance-id f97caa2686f14751b3b9b29d7e85a048 --list-recent-runs 12` showed GitHub workflow run `23289568217` with name `InternalApi-f97caa2686f14751b3b9b29d7e85a048`, status `completed`, and conclusion `success`.
- Files changed: `src/Template.Api/appsettings.Development.json`; `src/Template.Functions/appsettings.Development.json`; repo-local diagnostic files under `tmp/ghdiag`; `docs/github-workflow-direct-callback-migration-plan.md`
- Findings: The original GitHub JWT failure was not caused by missing Key Vault access. The loaded private key was valid, but it matched the dev GitHub App rather than the previously configured local app metadata. After correcting local `Github` settings and re-enabling API Key Vault usage, the supported API start path worked, GitHub dispatch succeeded, and the GitHub Actions workflow completed successfully. However, no corresponding local API webhook request or durable external event was observed for the instance, so the remaining local benchmark blocker is inbound webhook delivery back to the local stack.
- Feed-forward updates applied to later phases: Added evidence that dispatch and workflow execution now work locally, narrowed the remaining pre-migration blocker to webhook delivery, and recorded that the current active GitHub App guidance still points webhook traffic at the deployed dev API instead of the local API.
- Remaining risks: Phase 0 is still not closed. Although the current webhook-based system can now dispatch and complete a GitHub Actions run from local code, webhook callback delivery has not been observed locally, so the pre-migration end-to-end webhook benchmark remains incomplete on this machine.

- Date: 2026-03-20
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Re-ran the current webhook-based flow with the `Web Api Starter (Local)` GitHub App webhook URL pointed at the developer-owned dev tunnel `https://sqpnctzk-5000.uks1.devtunnels.ms/api/github/webhooks`, started Azurite via the checked-in task script, started the local API and Functions hosts, triggered the supported proxied API workflow-start path using a valid bearer token, and captured API logs, Functions host logs, and Azurite-backed Durable state showing end-to-end completion.
- Verification run: `build solution`; task `start azurite` (runs `tools/azurite/azurite-run.ps1`); `dotnet run --project ./src/Template.Api`; `func start --port 7071 --verbose` from `src/Template.Functions/bin/Debug/net10.0`; `devtunnel host web-api-starter-api-christian`; `curl -sk https://localhost:5000/health`; `curl -s http://localhost:7071/api/Echo`; `curl -sk -X POST https://localhost:5000/api/workflow/start -H 'Authorization: Bearer <token>' -H 'Content-Type: application/json' -d '{"WorkflowFile":"webhook-integration-test.yml","ReRunEntireWorkflow":true}'` returned `{"id":"42cf976321bd4288a18a3dc54e3e6228"}`; `AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1 az storage entity query --table-name TestHubNameInstances ...` showed `RuntimeStatus=Completed`; `AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1 az storage entity query --table-name TestHubNameHistory --filter "PartitionKey eq '42cf976321bd4288a18a3dc54e3e6228'" ...` showed `ExecutionStarted`, `TaskScheduled`, `TaskCompleted`, `EventRaised` (`WorkflowInProgress`, `WorkflowCompleted`), and `ExecutionCompleted`.
- Files changed: `docs/github-workflow-direct-callback-migration-plan.md`
- Findings: The supported API path now works end to end in the legacy webhook architecture when the local API is hosted behind the developer-specific dev tunnel and the `Web Api Starter (Local)` GitHub App webhook URL points at that tunnel. API logs showed the proxied `POST /api/workflow/start` request succeeded, followed by three inbound `POST /api/github/webhooks` deliveries. The first was an unrelated `Orchestrator Test Workflow` event that the API logged as unsupported. The next two were forwarded to the local Functions `GithubWebhook` endpoint, which raised durable external events `WorkflowInProgress` with GitHub run id `23353310577` and `WorkflowCompleted` with input `true`. The orchestrator instance `42cf976321bd4288a18a3dc54e3e6228` then reached terminal state `Completed` in Azurite-backed Durable storage.
- Feed-forward updates applied to later phases: Recorded the concrete local webhook-verification recipe using a persistent dev tunnel and the local GitHub App, confirmed that end-to-end webhook delivery can now be reproduced locally before migration, and noted that unrelated `workflow_run` deliveries may appear in logs and should be distinguished from the target orchestration instance during later comparisons.
- Remaining risks: Phase 0 is now closed for the current webhook-based design. The remaining migration risks are forward-looking: later phases must preserve the currently verified API-trigger, dispatch, and orchestration semantics while replacing webhook completion delivery with the direct callback path.

---

## Phase 1: Define And Isolate The New Callback Contract

### Goal

Create the new direct callback contract in the Functions project without yet tearing out the webhook path. The result of this phase is a clear, compilable direct-callback model and a neutral naming scheme that the rest of the migration can build on.

### Steps

- [ ] Introduce a neutral callback concept in the Functions project, for example `GithubWorkflowCallback` or `GithubWorkflowStatusCallback`.
- [ ] Move orchestration event names out of the current webhook class into a neutral shared type so the orchestrator is no longer coupled to `GithubWebhook`.
- [ ] Define a direct callback payload model carrying at least:
  - `instanceId`
  - `workflowName`
  - `runId`
  - `status`
  - `conclusion`
  - `runAttempt`
  - repository metadata if needed for diagnostics
- [ ] Decide and implement the new Function route, avoiding `github/webhooks` naming.
- [ ] Add request validation rules for the direct callback payload.
- [ ] Update any orchestration code that references event constants from the old webhook class.
- [ ] Build the Functions project.
- [ ] Update the checklist for this phase.
- [ ] Feed forward any naming, payload, or event-contract findings into Phases 2 through 6.

### Verification

1. `build functions` succeeds.
2. The orchestrator compiles against the new neutral event contract.
3. A repo search shows the new callback model and route exist.

### Feed Forward

- Phase 0 showed that local baseline validation is currently blocked before any callback contract behavior is exercised. Keep Phase 1 changes limited to contract and naming isolation, and do not treat the current local benchmark as proof that the webhook path is healthy.

---

## Phase 2: Replace The Functions Webhook Receiver With A Direct Authenticated Endpoint

### Goal

Swap the current webhook-triggered Functions receiver for a direct HTTP callback endpoint that raises the same Durable events.

### Steps

- [ ] Replace [src/Template.Functions/GithubWorkflowOrchestrator/GithubWebhook.cs](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Functions/GithubWorkflowOrchestrator/GithubWebhook.cs) with the new direct-callback HTTP trigger, or rename the file and class accordingly.
- [ ] Remove webhook-specific deserialization of `WorkflowRunEvent`.
- [ ] Raise `in progress` and `completed` Durable events from the new direct payload.
- [ ] Preserve idempotent logging and defensive validation.
- [ ] Keep the Function protected by Easy Auth expectations rather than anonymous public webhook semantics.
- [ ] Ensure the new endpoint returns clear failure responses for invalid payloads.
- [ ] Build the Functions project.
- [ ] If practical, add or update tests covering payload validation and event mapping.
- [ ] Update the checklist for this phase.
- [ ] Feed forward any endpoint, payload, or auth assumptions into Phases 3 through 6.

### Verification

1. `build functions` succeeds.
2. The new endpoint compiles and the old webhook-specific model dependency is no longer required in that function.
3. A targeted search confirms no Function trigger route still points at the old webhook callback path unless intentionally retained temporarily.

### Feed Forward

- Phase 0 exposed two local validation prerequisites for later direct-callback work: a valid GitHub App private key/JWT source is required before any GitHub dispatch-based comparison is meaningful, and local API invocation needs an explicit bearer-token acquisition step if the benchmark continues to go through the proxied API route.

---

## Phase 3: Enable GitHub Actions To Authenticate And Call The Function App Directly

### Goal

Authorize the GitHub Actions service principal to call the Internal API Function App and prove the workflow can acquire the right token audience, while preparing a safe per-environment cutover.

### Steps

- [ ] Update [tools/infrastructure/arm-templates/internal-api.bicep](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/arm-templates/internal-api.bicep) so the Function App app registration grants the app-only role to the correct GitHub Actions principal id for each environment.
- [ ] Trace where `allowedPrincipalIds` is supplied to the `internal-api.bicep` module and update that parent composition logic.
- [ ] Verify the principal ids sourced from [set-azure-connection-variables.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/azure-login/set-azure-connection-variables.ps1) flow correctly into deployment.
- [ ] Confirm the expected token audience remains `api://{functionAppName}`.
- [ ] Document the current GitHub App webhook settings for the environment being migrated:
   - webhook URL
   - subscribed events
   - operational owner
   - rollback steps to restore webhook delivery if needed
- [ ] Prepare the GitHub-side change needed to disable webhook delivery for the target environment once direct callback verification is ready.
- [ ] Update the showcase workflow [webhook-integration-test.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/workflows/webhook-integration-test.yml) to:
  - sign in with the custom Azure login action
  - export the required convention and infrastructure variables
  - obtain an access token for the Function App audience
  - call the new endpoint for the `in progress` signal
  - call the new endpoint for the `completed` signal in a final step
- [ ] Ensure only the initiating execution path sends the direct callbacks.
- [ ] Keep direct callback code dark or non-default until the per-environment cutover phase is complete.
- [ ] Build the solution.
- [ ] Update the checklist for this phase.
- [ ] Feed forward workflow/auth findings into Phases 4 through 6.

### Verification

1. `build solution` succeeds.
2. The workflow YAML contains direct authenticated callback steps and no longer describes webhook callback handling for the showcase path.
3. Infrastructure diffs show the GitHub Actions principal receives the expected app role assignment.
4. If deployment validation is available, confirm the Function App Easy Auth audience and authorized callers are correct.

### Feed Forward

- Pending.

---

## Phase 4: Per-Environment Cutover To Prevent Competing Event Delivery

### Goal

For each environment, prevent webhook and direct callback delivery from competing for the same orchestration events.

### Steps

- [ ] Choose the target environment for cutover.
- [ ] Disable GitHub App webhook delivery for that environment before direct callbacks go live.
- [ ] Verify the webhook configuration change has taken effect for that environment.
- [ ] Use code or configuration-based suppression only if GitHub-side disablement is temporarily blocked.
- [ ] Enable the direct callback path for that same environment.
- [ ] Run an environment-scoped validation that proves only one channel is producing orchestration events.
- [ ] Verify rollback instructions are tested and documented.
- [ ] Update the checklist for this phase.
- [ ] Feed forward any cutover sequencing or rollback findings into Phases 5 through 7.

### Verification

1. For the target environment, only the direct callback path produces orchestration events.
2. No duplicate `in progress` or `completed` events are observed for the same orchestration instance.
3. GitHub App webhook delivery is confirmed disabled for the target environment, or an explicit temporary suppression exception is documented.
4. Rollback steps are documented and usable.

### Feed Forward

- Pending.

---

## Phase 5: Remove API-Side GitHub Webhook Processing And Package Dependencies

### Goal

Eliminate the API project as a GitHub webhook receiver and remove webhook-specific package dependencies from the app projects.

### Steps

- [ ] Delete [src/Template.Api/Endpoints/GithubWebhookProxy/WorkflowRunWebhookProcessor.cs](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/Endpoints/GithubWebhookProxy/WorkflowRunWebhookProcessor.cs).
- [ ] Remove the webhook processor DI registration from [src/Template.Api/Program.cs](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/Program.cs).
- [ ] Remove `MapGitHubWebhooks` and any webhook-only rate limiting from [src/Template.Api/Program.cs](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/Program.cs).
- [ ] Remove `Octokit.Webhooks.AspNetCore` from [src/Template.Api/Template.Api.csproj](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/Template.Api.csproj).
- [ ] Remove `Octokit.Webhooks` from [src/Template.Functions/Template.Functions.csproj](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Functions/Template.Functions.csproj) if no remaining valid dependency exists.
- [ ] Remove webhook-specific configuration from [src/Template.Api/appsettings.json](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/appsettings.json) and [src/Template.Api/appsettings.Development.json](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/appsettings.Development.json).
- [ ] Remove any webhook-only logging overrides and settings classes.
- [ ] Build the API, Functions, and full solution.
- [ ] Search the repo for obsolete runtime references to webhook code paths.
- [ ] Update the checklist for this phase.
- [ ] Feed forward cleanup findings into Phases 6 and 7.

### Verification

1. `build api` succeeds.
2. `build functions` succeeds.
3. `build solution` succeeds.
4. A search confirms there are no live app references to:
   - `MapGitHubWebhooks`
   - `WebhookEventProcessor`
   - `Octokit.Webhooks`
   - `Github:WebhookSecret`

### Feed Forward

- Pending.

---

## Phase 6: Remove Webhook Dependency From Infrastructure Scripts And Operational Tooling

### Goal

Stop scripts, conventions, and support workflows from requiring GitHub webhook configuration.

### Steps

- [ ] Update [tools/infrastructure/ps-functions/Get-ResourceConvention.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/ps-functions/Get-ResourceConvention.ps1) so GitHub conventions no longer expose a webhook URL as a required output.
- [ ] Update [tools/infrastructure/upload-github-app-secrets.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/upload-github-app-secrets.ps1) to stop accepting, displaying, or uploading webhook secrets.
- [ ] Update [tools/infrastructure/generate-github-app-servicenow-ticket.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/generate-github-app-servicenow-ticket.ps1) so it requests an Actions-permissions app only.
- [ ] Search `tools/infrastructure/` for webhook-era terminology and remove or rewrite it.
- [ ] If any scripts are intended to be run in dry-run mode, execute those dry runs and inspect the output.
- [ ] Build the solution if any shared code or settings are touched.
- [ ] Update the checklist for this phase.
- [ ] Feed forward tooling and wording findings into Phase 6.

### Verification

1. Dry-run output from updated support scripts no longer mentions webhook URL or webhook secret.
2. Repo search under `tools/infrastructure/` confirms webhook-specific setup has been removed or intentionally deprecated.
3. If shared project files were touched, `build solution` succeeds.

### Feed Forward

- Pending.

---

## Phase 7: Rewrite Documentation For The Direct Callback Architecture

### Goal

Align all repository documentation with the new design so contributors no longer set up or reason about GitHub workflow completion through webhooks.

### Steps

- [ ] Rewrite [docs/workflow-orchestration-setup.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/workflow-orchestration-setup.md) around the direct callback flow, Entra auth, callback payload, and fallback polling behavior.
- [ ] Update [docs/github-app-creation.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/github-app-creation.md) to remove webhook URL and webhook secret setup requirements.
- [ ] Update [docs/add-environment.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/add-environment.md) to remove webhook prerequisites.
- [ ] Search `docs/` for stale references to GitHub webhook setup, webhook secret upload, or webhook callback routing.
- [ ] Update architecture diagrams and sequence diagrams to reflect GitHub Actions calling the Functions app directly.
- [ ] Build the solution only if any code snippets or references required code edits.
- [ ] Update the checklist for this phase.
- [ ] Feed forward any rollout caveats into the Final Readiness Review section below.

### Verification

1. A `docs/` search shows the primary guidance no longer instructs users to configure GitHub webhooks for workflow completion.
2. The updated diagrams and sequences match the implemented route and auth model.
3. The migration plan document remains consistent with the final code and docs state.

### Feed Forward

- Pending.

---

## Final Readiness Review

Do not mark the migration complete until all items below are true.

- [ ] A pre-migration benchmark of the original webhook-based design was captured and is available for comparison.
- [ ] The benchmark includes captured host log evidence and Azurite-backed Durable state inspection for a real orchestration instance.
- [ ] The workflow can authenticate with Azure and call the Function endpoint directly.
- [ ] The Function endpoint raises both Durable events correctly.
- [ ] The orchestrator still works when a callback is delayed or missing and fallback polling is required.
- [ ] Each migrated environment has only one active orchestration event delivery path.
- [ ] The API project is no longer a GitHub webhook receiver.
- [ ] Webhook packages and webhook configuration have been removed from the application projects.
- [ ] Infra scripts and support-ticket generation no longer require webhook setup.
- [ ] Docs no longer describe webhook completion delivery as the supported design.
- [ ] Repo-wide search confirms no unintended webhook-era runtime behavior remains.

## Suggested Working Log Pattern For Each Phase

At the end of each phase, append a short execution log using this structure:

### Phase N Execution Log

- Date:
- Agent:
- Summary of completed work:
- Verification run:
- Files changed:
- Findings:
- Feed-forward updates applied to later phases:
- Remaining risks:

This keeps the plan document current while the migration is being executed incrementally.