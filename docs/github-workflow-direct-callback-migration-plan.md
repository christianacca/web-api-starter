# GitHub Workflow Queue Callback Migration Plan

## Purpose

Replace GitHub `workflow_run` webhook delivery with GitHub Actions publishing queue messages to the Function App storage account `default-queue`.

The migration must be executed in verifiable phases. Each phase should end with:

1. a working system state for that phase,
2. explicit verification, preferably automated,
3. checklist updates for completed steps, and
4. a phase commit on the current branch when the phase produced file changes and verification passed, and
5. feed-forward updates to future phases based on what was learned.

## Target Architecture

The steady-state design is:

1. The Functions app dispatches a GitHub workflow.
2. The workflow authenticates to Azure using the existing GitHub OIDC plus Entra service principal pattern.
3. The workflow publishes completion messages to the Function App storage account `default-queue`.
4. A queue-triggered Functions handler reads those messages and raises the same Durable external events currently used by the orchestrator.
5. The API project no longer receives GitHub webhooks for workflow completion.
6. The repo no longer depends on GitHub App webhook configuration or webhook secrets.

## Decisions Already Made

1. Preserve both orchestration signals.
   The workflow will publish:
   - an `in progress` queue message carrying the `runId`
   - a `completed` queue message carrying final outcome data
2. Remove GitHub App webhook dependency entirely.
3. Update support-ticket generation to request a GitHub App for Actions permissions only.
4. Reuse the existing `default-queue`.
   `ExampleQueue` remains the owner of `default-queue`, and the existing message envelope plus dispatch pattern stays in place.
5. Avoid dual delivery competition within an environment.
   For any environment being migrated, webhook-driven orchestration events and queue-driven orchestration events must not both be active at the same time.
6. Preferred cutover strategy: disable webhook delivery at the source.
   For each environment, the preferred approach is to disable GitHub App webhook delivery before enabling queue publishing in that environment. Code-based suppression is a fallback option only if GitHub-side reconfiguration cannot be completed safely in time.
7. Use Azure CLI for workflow queue publication.
   The publishing path should use `az storage message put --auth-mode login` from checked-in scripts or composite actions, not ad hoc REST calls and not shared-key authentication.
8. Use least-privilege queue sender RBAC.
   The GitHub Actions service principal should receive the built-in `Storage Queue Data Message Sender` role on the Function App storage account scope that owns `default-queue`.
9. Keep queue transport as raw JSON.
   Publishers should send the queue message content as one JSON-serialized `MessageBody` document. `MessageBody.Data` remains a JSON string containing the serialized inner payload. Do not manually base64-encode the envelope or the inner payload.
10. Use one reusable workflow queue publisher action.
   The `in progress` and `completed` publications should go through the same dedicated composite action and the same local PowerShell script, with message type and payload as inputs.
11. Fail fast on authorization or publish problems.
   If app resolution, environment authorization, Azure login, storage discovery, or queue publication fails, the workflow must fail rather than silently skip or degrade to polling-only behavior.
12. Treat queue delivery as at-least-once.
   Publishers and consumers must assume duplicate queue messages are possible. The Functions-side workflow message handling must therefore be idempotent for repeated `GithubWorkflowInProgress` and `GithubWorkflowCompleted` messages carrying the same correlation fields.

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
   Before enabling queue-based completion delivery for a given environment, disable or suppress webhook-based event raising for that same environment so both channels cannot compete.
8. Prefer source-side elimination over application-side suppression.
   If webhook delivery can be disabled in GitHub for an environment, do that instead of adding temporary code to ignore duplicate deliveries.
9. If reusing `default-queue`, keep a single queue-triggered owner for that queue.
   Do not create multiple independent queue-triggered Functions bound to `default-queue` unless the plan explicitly changes queue ownership semantics.
10. Keep the existing queue message handling pattern.
   Extend `ExampleQueue` using the current `MessageBody` and `QueueMessageMetadata` routing model rather than introducing a second queue consumer or a second queue envelope format.
11. Make `github-app-authz-envs` fail closed.
   The workflow authorization step must fail the workflow when the dispatching GitHub App is not authorized for any of the environments that the workflow is actually attempting to run.
12. Centralize the `in progress` message publication.
   `github-app-authz-envs` should become the single bootstrap step that resolves the authorized target environments, signs into Azure for the primary environment, and publishes the `in progress` queue message exactly once.
13. Accept workflow-gated environments as a multi-line YAML input.
   The workflow should pass its gated environments to `github-app-authz-envs` as a newline-delimited block scalar, not as inferred job metadata.
14. Keep queue publication logic in checked-in scripts or composite actions.
   Do not inline complex JSON construction or `az storage` commands directly into workflow YAML when the same logic can live in a versioned script or reusable publisher action.
15. Do not use storage keys, connection strings, or SAS for GitHub workflow publication.
   The steady-state design is Entra-authenticated queue publication only.
16. Make correlation fields the deduplication contract.
   For workflow queue messages, treat `instanceId`, `runId`, `runAttempt`, and `MessageType` as the minimum correlation tuple used to recognize duplicates and guard idempotent processing.
17. Make human intervention explicit.
   Every phase should state whether it expects human intervention and whether there is an approval gate before the phase can be considered complete.
18. Commit only verified phase work.
   If a phase produces file changes, create one commit on the current branch only after that phase passes verification and its checklist/feed-forward updates are complete.
19. Create the pull request only after final readiness passes.
   Do not open the PR until the migration is complete enough to satisfy the Final Readiness Review, unless a human explicitly chooses an earlier draft-PR workflow.

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
7. For queue phases, verify queue message publication, dequeue behavior, and poison-queue handling where relevant.

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
- [x] If this phase produced file changes, create one commit on the current branch after verification passed.
- [x] Feed forward any setup, observability, or reproducibility findings into Phases 1 through 7.

### Verification

1. `build solution` succeeds on the unmodified codebase.
2. The current API and Functions apps start locally.
3. A real orchestration run is observed locally and reaches the expected state.
4. The current webhook-based event flow is confirmed with Functions host logs.
5. Durable state for the captured `instanceId` is confirmed against Azurite-backed storage using a reproducible inspection method.
6. A reproducible benchmark record exists for later comparison.

### Human Intervention

- None expected if the local machine already has the required credentials, local secrets, tunnel access, and GitHub App configuration needed to reproduce the benchmark.

### Approval Gate

- None expected.

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
- Remaining risks: Phase 0 is now closed for the current webhook-based design. The remaining migration risks are forward-looking: later phases must preserve the currently verified API-trigger, dispatch, and orchestration semantics while replacing webhook completion delivery with the queue-based path.

---

## Phase 1: Define And Isolate The Queue Message Contract

### Goal

Create the new workflow-completion queue message contract in the Functions project without yet tearing out the webhook path. The result of this phase is a clear, compilable queue message model, neutral orchestration naming, and a fixed plan that extends `ExampleQueue` as the owner of `default-queue`.

### Steps

- [ ] Introduce a neutral workflow-completion queue message concept in the Functions project, for example `GithubWorkflowQueueMessage` or `GithubWorkflowCompletionMessage`.
- [ ] Move orchestration event names out of the current webhook class into a neutral shared type so the orchestrator is no longer coupled to `GithubWebhook`.
- [ ] Define a queue message payload model carrying at least:
  - `instanceId`
  - `workflowName`
  - `runId`
  - `status`
  - `conclusion`
  - `runAttempt`
  - repository metadata if needed for diagnostics
- [ ] Define the new workflow-completion message type so it fits the existing `ExampleQueue` dispatch pattern on `default-queue`.
- [ ] Reuse the existing `MessageBody` plus `QueueMessageMetadata` envelope and do not introduce a second queue envelope format.
- [ ] Fix the stable `QueueMessageMetadata.MessageType` names for the workflow message contract.
- [ ] Add validation rules for the new workflow-completion queue payload and message metadata.
- [ ] Fix the exact minimum JSON payload fields for both `GithubWorkflowInProgress` and `GithubWorkflowCompleted`.
- [ ] Update any orchestration code that references event constants from the old webhook class.
- [ ] Build the Functions project.
- [ ] Update the checklist for this phase.
- [ ] If this phase produced file changes, create one commit on the current branch after verification passed.
- [ ] Feed forward any naming, message-shape, queue-ownership, or event-contract findings into Phases 2 through 7.

### Verification

1. `build functions` succeeds.
2. The orchestrator compiles against the new neutral event contract.
3. A repo search shows the new queue message model exists.
4. The plan explicitly extends `ExampleQueue` as the sole owner of `default-queue` and does not introduce competing queue-triggered consumers.
5. The stable workflow queue message type names and minimum payload fields are explicitly documented.

### Human Intervention

- None expected.

### Approval Gate

- None expected.

### Feed Forward

- Phase 0 is now complete. Keep Phase 1 changes limited to message contract and queue ownership isolation so the verified webhook benchmark remains a stable comparison point.

---

## Phase 2: Replace The Functions Webhook Receiver With Queue Consumption

### Goal

Swap the current webhook-triggered Functions receiver for queue-driven processing that raises the same Durable events.

### Steps

- [ ] Replace [src/Template.Functions/GithubWorkflowOrchestrator/GithubWebhook.cs](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Functions/GithubWorkflowOrchestrator/GithubWebhook.cs) with queue-driven workflow-completion handling, or rename the file and class accordingly.
- [ ] Remove webhook-specific deserialization of `WorkflowRunEvent`.
- [ ] Implement workflow-completion message handling in `ExampleQueue` on `default-queue` without creating multiple competing triggers on the same queue.
- [ ] Raise `in progress` and `completed` Durable events from the new queue payload.
- [ ] Preserve idempotent logging and defensive validation.
- [ ] Make queue processing idempotent for duplicate `GithubWorkflowInProgress` and `GithubWorkflowCompleted` deliveries that repeat the same `instanceId`, `runId`, `runAttempt`, and message type.
- [ ] Ensure invalid or unsupported queue messages fail in a controlled way and use the poison-queue path appropriately through the existing `ExampleQueue` handling model.
- [ ] Update any development queue initialization if additional queue artifacts are required.
- [ ] Build the Functions project.
- [ ] If practical, add or update tests covering payload validation and event mapping.
- [ ] Update the checklist for this phase.
- [ ] If this phase produced file changes, create one commit on the current branch after verification passed.
- [ ] Feed forward any queue processing, poison-handling, or message-routing assumptions into Phases 3 through 7.

### Verification

1. `build functions` succeeds.
2. The new queue-driven handler compiles and the old webhook-specific model dependency is no longer required in that function.
3. A targeted search confirms `ExampleQueue` remains the sole `default-queue` owner and now handles the workflow-completion message type.
4. Poison-queue behavior for unsupported or invalid messages is understood and documented.
5. Duplicate workflow queue messages do not create duplicate durable side effects.

### Human Intervention

- None expected.

### Approval Gate

- None expected.

### Feed Forward

- Phase 0 exposed two local validation prerequisites for later queue-based work: a valid GitHub App private key/JWT source is required before any GitHub dispatch-based comparison is meaningful, and local API invocation needs an explicit bearer-token acquisition step if the benchmark continues to go through the proxied API route.

---

## Phase 3: Enable GitHub Actions To Authenticate And Publish To The Function App Queue

### Goal

Authorize the GitHub Actions service principal to publish messages to the Function App storage queue and prove the workflow can acquire the right queue access, while preparing a safe per-environment cutover.

### `github-app-authz-envs` Interface Contract

The plan for [github-app-authz-envs/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/github-app-authz-envs/action.yml) should use this contract.

Inputs:

1. `gated-environments`
   A required multi-line string input listing the workflow environments that are eligible to run for this workflow.

Example:

```yaml
with:
  gated-environments: |
    dev
    qa
    demo
```

Parsing rules:

1. Split on newlines.
2. Trim whitespace from each line.
3. Drop blank lines.
4. Preserve declared order.
5. Treat the resulting list as the workflow's allowed target environments.

Outputs:

1. `primary`
   The primary environment for the dispatching GitHub App.
2. `pipeline`
   The dispatching GitHub App's full authorized pipeline environment list as JSON.
3. `authorized-target-envs`
   The ordered intersection between `gated-environments` and the app-authorized pipeline environments, serialized as a JSON array for downstream `if` conditions.
   Expected shape:

```json
["dev","qa"]
```

4. `published-in-progress`
   Boolean-like output indicating whether the bootstrap `in progress` message was successfully published.

Behavior:

1. Resolve the dispatching GitHub App from `github.triggering_actor`.
2. Resolve that app's `primary` and `pipeline` environments.
3. Intersect the workflow's `gated-environments` input with the resolved pipeline environments.
4. Fail the workflow if the dispatching actor cannot be resolved to a supported GitHub App.
5. Fail the workflow if the intersection is empty.
6. Sign into Azure for the `primary` environment.
7. Discover the Function App storage account for that environment.
8. Publish exactly one bootstrap `in progress` message to `default-queue` for the primary environment by calling the reusable workflow queue publisher action, which is backed by a checked-in local PowerShell script that uses `az storage message put --auth-mode login`.
9. Fail the workflow if Azure login, storage discovery, or queue publication fails.
10. Export `authorized-target-envs` for downstream job gating.

Publication notes:

1. Add one reusable composite action dedicated to publishing workflow queue messages.
2. Back that composite action with one checked-in local PowerShell helper that builds the `MessageBody` JSON and invokes `az storage message put`.
3. The composite action should accept at least the message type, payload JSON, storage account, and queue name as inputs.
4. The script should pass the raw serialized `MessageBody` JSON through `--content`.
5. The script should not manually base64-encode the message body.
6. The script should emit a non-zero exit code on any publication failure so the calling action fails closed.
7. `github-app-authz-envs` may call this reusable publisher action for the bootstrap `GithubWorkflowInProgress` message after it has resolved authorization and signed into Azure.
8. The workflow should call the same reusable publisher action again from a final `if: always()` step for `GithubWorkflowCompleted`, gated so it only runs when the bootstrap path already succeeded, for example when `published-in-progress == 'true'`.

### Queue Message Contract Names

Use these stable `QueueMessageMetadata.MessageType` names for the workflow completion contract:

1. `GithubWorkflowInProgress`
2. `GithubWorkflowCompleted`

### Queue Message Contract Payloads

The plan treats the `MessageBody` envelope as fixed:

1. `MessageBody.Id`
   A unique message id generated by the publisher.
2. `MessageBody.Metadata.MessageType`
   One of the stable message type names above.
3. `MessageBody.Data`
   A JSON-serialized payload specific to the message type.

Proposed minimum payload for `GithubWorkflowInProgress`:

```json
{
  "instanceId": "42cf976321bd4288a18a3dc54e3e6228",
  "workflowName": "InternalApi-42cf976321bd4288a18a3dc54e3e6228",
  "runId": 23353310577,
  "runAttempt": 1,
  "environment": "dev",
  "repository": "christianacca/web-api-starter"
}
```

Proposed minimum payload for `GithubWorkflowCompleted`:

```json
{
  "instanceId": "42cf976321bd4288a18a3dc54e3e6228",
  "workflowName": "InternalApi-42cf976321bd4288a18a3dc54e3e6228",
  "runId": 23353310577,
  "runAttempt": 1,
  "status": "completed",
  "conclusion": "success",
  "environment": "dev",
  "repository": "christianacca/web-api-starter"
}
```

Design notes:

1. `instanceId` is the orchestration correlation key and must always be present.
2. `runId` is required on both message types so Durable event handling and later diagnostics remain consistent.
3. `runAttempt` should be included from the start even if the initial implementation only needs attempt `1`.
4. `environment` should refer to the primary environment used for queue publication.
5. `repository` should be the full `owner/repo` string for diagnostics and defensive validation.
6. Queue publishers should serialize the outer `MessageBody` once and should serialize the inner payload once into `MessageBody.Data`.
7. The Functions consumer should treat the tuple `instanceId` plus `runId` plus `runAttempt` plus message type as the minimum duplicate-detection key.
8. Repeated queue messages with the same duplicate-detection key must not cause duplicate durable side effects.

### Steps

- [ ] Identify the storage account that backs the Function App `default-queue` in each environment and trace how that account is expressed in conventions and deployment.
- [ ] Update infrastructure so the correct GitHub Actions principal id for each environment can publish queue messages to that storage account using the built-in `Storage Queue Data Message Sender` role at the storage account scope.
- [ ] Trace where those principal ids and storage scopes are composed in deployment and update that parent logic.
- [ ] Verify the principal ids sourced from [set-azure-connection-variables.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/azure-login/set-azure-connection-variables.ps1) flow correctly into deployment.
- [ ] Confirm the workflow has the storage account name, queue name, and `auth-mode login` inputs it needs to publish to `default-queue`.
- [ ] Document the current GitHub App webhook settings for the environment being migrated:
   - webhook URL
   - subscribed events
   - operational owner
   - rollback steps to restore webhook delivery if needed
- [ ] Prepare the GitHub-side change needed to disable webhook delivery for the target environment once queue-publication verification is ready.
- [ ] Update [github-app-authz-envs/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/github-app-authz-envs/action.yml) so it accepts a required multi-line `gated-environments` input.
- [ ] Update `github-app-authz-envs` so it computes the intersection between:
   - the workflow-gated environments passed in by the workflow, and
   - the dispatching GitHub App's authorized pipeline environments
- [ ] Make `github-app-authz-envs` fail the workflow if that intersection is empty.
- [ ] Update `github-app-authz-envs` outputs so downstream jobs consume `authorized-target-envs` rather than the unconstrained pipeline environment list.
- [ ] Preserve the existing `primary` and `pipeline` outputs unless a later phase proves they can be removed safely.
- [ ] Extend `github-app-authz-envs` to sign into Azure using the primary environment for the dispatching GitHub App.
- [ ] Add one reusable workflow queue publisher composite action backed by a local PowerShell script that uses `az storage message put --auth-mode login`.
- [ ] Extend `github-app-authz-envs` to discover the target storage account and publish the `in progress` message to `default-queue` for that primary environment by calling the reusable queue publisher action.
- [ ] Make `github-app-authz-envs` fail if actor resolution, environment authorization, Azure login, storage discovery, or bootstrap queue publication fails.
- [ ] Keep `github-app-authz-envs` focused on bootstrap behavior only. The `completed` queue message should be published later in the workflow by calling the same reusable queue publisher action from a final step that always runs.
- [ ] Update the showcase workflow [webhook-integration-test.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/workflows/webhook-integration-test.yml) to:
   - pass the workflow's gated environments into `github-app-authz-envs` using a multi-line YAML block scalar
   - consume the `authorized-target-envs` output from `github-app-authz-envs`
   - rely on `github-app-authz-envs` to publish the single bootstrap `in progress` message
   - publish the `completed` message to `default-queue` by invoking the same reusable queue publisher action in a final step that always runs
- [ ] Ensure only the bootstrap step publishes the `in progress` message and only the final completion step publishes the `completed` message.
- [ ] Ensure the final completion publisher step is guarded with `if: always()` and only attempts publication when the bootstrap path already reported `published-in-progress == 'true'`.
- [ ] Keep queue-based completion delivery dark or non-default until the per-environment cutover phase is complete.
- [ ] Build the solution.
- [ ] Update the checklist for this phase.
- [ ] If this phase produced file changes, create one commit on the current branch after verification passed.
- [ ] Feed forward workflow, storage-auth, and queue-publishing findings into Phases 4 through 7.

### Verification

1. `build solution` succeeds.
2. `github-app-authz-envs` fails closed when the dispatching GitHub App is not authorized for any workflow-gated environment.
3. The workflow YAML passes explicit gated environments into `github-app-authz-envs` using the documented multi-line input shape and consumes `authorized-target-envs` from that action.
4. `github-app-authz-envs` publishes exactly one `in progress` message for the primary environment.
5. The workflow publishes exactly one `completed` message from the same reusable queue publisher action in a final step.
6. Infrastructure diffs show the GitHub Actions principal receives the built-in `Storage Queue Data Message Sender` role on the expected storage account scope.
7. The reusable queue publication helper uses `az storage message put --auth-mode login` and does not fall back to shared keys, connection strings, or SAS.
8. If deployment validation is available, confirm the workflow can publish raw `MessageBody` JSON to the intended storage account and queue using the chosen auth mode.

### Human Intervention

- None expected for code changes, local validation, workflow/action authoring, or infrastructure-as-code modifications.
- Human intervention may be required only if verifying or applying the infrastructure change depends on running an approval-gated deployment workflow, using production-like environment approvals, or using credentials the agent cannot access directly.

### Approval Gate

- Treat this phase as autonomous by default.
- Only introduce an approval gate if applying or validating the infrastructure changes requires an environment deployment approval or a human-triggered deployment workflow run.

### Feed Forward

- Pending.

---

## Phase 4: Per-Environment Cutover To Prevent Competing Event Delivery

### Goal

For each environment, prevent webhook and queue-driven delivery from competing for the same orchestration events.

### Steps

- [ ] Choose the target environment for cutover.
- [ ] Disable GitHub App webhook delivery for that environment before queue publishing goes live.
- [ ] Verify the webhook configuration change has taken effect for that environment.
- [ ] Use code or configuration-based suppression only if GitHub-side disablement is temporarily blocked.
- [ ] Enable queue-based completion delivery for that same environment.
- [ ] Run an environment-scoped validation that proves only one channel is producing orchestration events.
- [ ] Verify rollback instructions are tested and documented.
- [ ] Update the checklist for this phase.
- [ ] If this phase produced file changes, create one commit on the current branch after verification passed.
- [ ] Feed forward any cutover sequencing or rollback findings into Phases 5 through 7.

### Verification

1. For the target environment, only the queue-based path produces orchestration events.
2. No duplicate `in progress` or `completed` events are observed for the same orchestration instance.
3. GitHub App webhook delivery is confirmed disabled for the target environment, or an explicit temporary suppression exception is documented.
4. Rollback steps are documented and usable.
5. The environment validation includes at least one duplicate-message probe or replay check proving the queue consumer remains idempotent after cutover.

### Human Intervention

- Expected for shared-environment cutover activities.
- A human may need to approve the choice of cutover environment, perform or authorize the GitHub-side webhook disablement, and confirm rollback ownership for the environment being changed.

### Approval Gate

- Required before enabling queue-based completion delivery for a real shared environment.

### Feed Forward

- Pending.

---

## Phase 5: Remove API-Side GitHub Webhook Processing And Package Dependencies

### Goal

Eliminate the API project as a GitHub webhook receiver and remove webhook-specific package dependencies from the app projects once queue-driven completion is proven.

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
- [ ] If this phase produced file changes, create one commit on the current branch after verification passed.
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

### Human Intervention

- None expected after the cutover phase is complete.

### Approval Gate

- None expected.

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
- [ ] Update conventions, deployment docs, or infra helpers as needed so the workflow can discover the Function App storage account and `default-queue` without relying on ad hoc secrets.
- [ ] Search `tools/infrastructure/` for webhook-era terminology and remove or rewrite it.
- [ ] If any scripts are intended to be run in dry-run mode, execute those dry runs and inspect the output.
- [ ] Build the solution if any shared code or settings are touched.
- [ ] Update the checklist for this phase.
- [ ] If this phase produced file changes, create one commit on the current branch after verification passed.
- [ ] Feed forward tooling and wording findings into Phase 7.

### Verification

1. Dry-run output from updated support scripts no longer mentions webhook URL or webhook secret.
2. Repo search under `tools/infrastructure/` confirms webhook-specific setup has been removed or intentionally deprecated, and queue-publication prerequisites are documented.
3. If shared project files were touched, `build solution` succeeds.

### Human Intervention

- None expected for the code and script changes themselves.
- Human intervention may be required if validating the updated scripts depends on protected infrastructure, organizational process ownership, or credentials unavailable to the agent.

### Approval Gate

- None by default.
- Add an approval gate only if script validation must run against protected shared infrastructure.

### Feed Forward

- Pending.

---

## Phase 7: Rewrite Documentation For The Queue-Based Architecture

### Goal

Align all repository documentation with the new design so contributors no longer set up or reason about GitHub workflow completion through webhooks.

### Steps

- [ ] Rewrite [docs/workflow-orchestration-setup.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/workflow-orchestration-setup.md) around the queue-based completion flow, workflow auth to Azure Storage, queue message shape, queue-trigger processing, and fallback polling behavior.
- [ ] Document the revised role of [github-app-authz-envs/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/github-app-authz-envs/action.yml) as the fail-closed workflow authorization and `in progress` bootstrap publisher.
- [ ] Document the `gated-environments` multi-line input contract and the `authorized-target-envs` output contract for [github-app-authz-envs/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/github-app-authz-envs/action.yml).
- [ ] Document the reusable workflow queue publisher composite action and its local PowerShell helper, including how it is used for both `GithubWorkflowInProgress` and `GithubWorkflowCompleted`.
- [ ] Document that queue publication uses `az storage message put --auth-mode login` with the built-in `Storage Queue Data Message Sender` role and no shared-key fallback.
- [ ] Document the raw `MessageBody` JSON transport format, including that `MessageBody.Data` contains a JSON string payload rather than a second envelope.
- [ ] Document the duplicate-handling contract for repeated workflow queue messages.
- [ ] Update [docs/github-app-creation.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/github-app-creation.md) to remove webhook URL and webhook secret setup requirements.
- [ ] Update [docs/add-environment.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/add-environment.md) to remove webhook prerequisites.
- [ ] Search `docs/` for stale references to GitHub webhook setup, webhook secret upload, or webhook callback routing.
- [ ] Update architecture diagrams and sequence diagrams to reflect GitHub Actions publishing queue messages to `default-queue`.
- [ ] Build the solution only if any code snippets or references required code edits.
- [ ] Update the checklist for this phase.
- [ ] If this phase produced file changes, create one commit on the current branch after verification passed.
- [ ] Feed forward any rollout caveats into the Final Readiness Review section below.

### Verification

1. A `docs/` search shows the primary guidance no longer instructs users to configure GitHub webhooks for workflow completion.
2. The updated diagrams and sequences match the implemented route and auth model.
3. The migration plan document remains consistent with the final code and docs state.

### Human Intervention

- None expected.

### Approval Gate

- None expected.

### Feed Forward

- Pending.

---

## Final Readiness Review

Do not mark the migration complete until all items below are true.

- [ ] A pre-migration benchmark of the original webhook-based design was captured and is available for comparison.
- [ ] The benchmark includes captured host log evidence and Azurite-backed Durable state inspection for a real orchestration instance.
- [ ] The workflow can authenticate with Azure and publish both required messages to the intended storage queue.
- [ ] The workflow publishes through `az storage message put --auth-mode login` using the built-in `Storage Queue Data Message Sender` role on the intended storage account.
- [ ] Queue-driven processing raises both Durable events correctly.
- [ ] Queue message transport uses raw serialized `MessageBody` JSON with no manual base64 encoding.
- [ ] Duplicate workflow queue messages have been tested and do not create duplicate durable side effects.
- [ ] The orchestrator still works when a callback is delayed or missing and fallback polling is required.
- [ ] Each migrated environment has only one active orchestration event delivery path.
- [ ] The API project is no longer a GitHub webhook receiver.
- [ ] Webhook packages and webhook configuration have been removed from the application projects.
- [ ] Infra scripts and support-ticket generation no longer require webhook setup.
- [ ] Docs no longer describe webhook completion delivery as the supported design.
- [ ] Repo-wide search confirms no unintended webhook-era runtime behavior remains.

## Final Delivery

Complete this section only after the Final Readiness Review passes.

### Steps

- [ ] Confirm the current branch contains one verified commit per completed phase, where that phase produced file changes.
- [ ] Push the current branch to the remote if it is not already pushed.
- [ ] Create a pull request from the current branch into `master`.
- [ ] Summarize the migration in the pull request body, including:
   - phase-by-phase commit summary
   - verification evidence or commands run
   - any remaining risks or rollout caveats
   - any explicitly deferred follow-up work

### Human Intervention

- Expected for repository delivery activities.
- A human may need to authenticate for push access, satisfy repository policy, review the final diff, or approve opening the pull request.

### Approval Gate

- Introduce an approval gate only if repository policy or branch governance requires human approval before opening the final pull request.

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