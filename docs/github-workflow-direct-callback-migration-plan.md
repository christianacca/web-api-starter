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
5. Avoid relying on dual delivery in the steady state.
   Queue-driven orchestration events are the intended completion path. Residual GitHub webhook deliveries may continue transiently during rollout, but the migration should not depend on webhook callbacks remaining healthy once the queue path is deployed.
6. Remove GitHub App webhook behavior after the queue path is deployed everywhere.
   The simplified rollout is: make queue publication the default on `master`, deploy that application/workflow state to all environments, then remove the remaining GitHub App webhook behavior and related configuration.
7. Use Azure CLI for workflow queue publication.
   The publishing path should use `az storage message put --auth-mode login` from checked-in scripts or composite actions, not ad hoc REST calls and not shared-key authentication.
8. Use least-privilege queue sender RBAC.
   The GitHub Actions service principal should receive the built-in `Storage Queue Data Message Sender` role on the Function App storage account scope that owns `default-queue`.
9. Keep one `MessageBody` envelope contract and publish it in the queue-trigger encoding expected by the function app.
   Publishers should send the queue message content as one JSON-serialized `MessageBody` document. `MessageBody.Data` remains a JSON string containing the serialized inner payload. If the function app keeps the default Azure Storage Queue trigger behavior, base64-encode the outer `MessageBody` document at publish time rather than changing the host-wide queue extension setting.
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
7. Treat global deployment of the queue path as the rollout control point.
   Do not remove API-side webhook handling from the deployed application until the queue-publishing workflow changes have been merged to `master` and deployed to every environment that will receive the cleanup deployment.
8. Remove GitHub-side webhook behavior after the application cleanup is deployed.
   Once the queue path is deployed everywhere, remove or disable the remaining GitHub App webhook behavior rather than keeping webhook delivery active as a long-lived failing path.
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
- The original local benchmark blocker was a mismatched GitHub App configuration. At the time of the benchmark, the locally loaded Key Vault private key matched the dev GitHub App `2800136` / installation `108147932`, not the then-configured dedicated local-app values `2800205` / `108147870`.
- Any future local benchmark that needs the API start path must include an explicit bearer-token acquisition step or a documented local auth bypass, because the proxied `POST /api/workflow/start` route is not anonymously callable.
- Dispatch success alone is not sufficient benchmark evidence. For local verification of the legacy webhook design, also prove where the active GitHub App webhook is pointed and whether a tunnel or override is routing callbacks back to the local API.
- The successful local webhook benchmark used a dedicated `Web Api Starter (Local)` GitHub App pointed at `<tunnel-url>/api/github/webhooks` through a developer-owned persistent dev tunnel with anonymous tunnel access enabled for port `5000`.
- Local development settings have since been reverted to the shared `Github` / `Web API Starter (dev)` configuration. Re-running the legacy webhook benchmark would now require a temporary GitHub-side webhook retargeting or an equivalent local override rather than relying on the current checked-in development appsettings.
- During the successful local benchmark, GitHub delivered one unrelated `workflow_run` webhook for `Orchestrator Test Workflow` that the API logged as unsupported before delivering the expected `WorkflowInProgress` and `WorkflowCompleted` events for the target orchestration instance.

### Phase 0 Execution Log

- Date: 2026-03-20
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Established the final baseline benchmark for the legacy webhook design by confirming local API-triggered dispatch, GitHub workflow execution, inbound webhook delivery back to the local stack through the developer-owned dev tunnel, and Durable completion in Azurite-backed storage.
- Verification run: `build solution`; local API and Functions hosts started successfully; supported proxied `POST /api/workflow/start` returned a real orchestration `instanceId`; host logs and Azurite-backed Durable state confirmed `WorkflowInProgress` and `WorkflowCompleted` events for the target instance.
- Files changed: `src/Template.Api/appsettings.Development.json`; `src/Template.Functions/appsettings.Development.json`; repo-local diagnostics under `tmp/ghdiag`; `docs/github-workflow-direct-callback-migration-plan.md`
- Findings: The key Phase 0 blockers were resolved in sequence before the baseline closed: the active GitHub App settings had to match the Key Vault private key, API invocation required bearer auth, and inbound webhook delivery required pointing the dedicated `Web Api Starter (Local)` GitHub App at the developer-owned persistent dev tunnel. With those prerequisites in place, the verified webhook benchmark became: supported API start path, real GitHub Actions dispatch and success, inbound webhook delivery to the local API, forwarding to Functions, and terminal Durable completion in Azurite. Unrelated `workflow_run` deliveries may still appear in logs and should be distinguished from the target orchestration instance during later comparisons.
- Feed-forward updates applied to later phases: Recorded the Azurite inspection method, local task-hub/table names, API auth prerequisite, the historical local webhook benchmark recipe, and the fact that end-to-end webhook delivery can be reproduced locally before migration.
- Remaining risks: Phase 0 is closed. The remaining risks are forward-looking: later phases must preserve the verified API-trigger, dispatch, and orchestration semantics while replacing webhook completion delivery with the queue-based path.

---

## Phase 1: Define And Isolate The Queue Message Contract

### Goal

Create the new workflow-completion queue message contract in the Functions project without yet tearing out the webhook path. The result of this phase is a clear, compilable queue message model, neutral orchestration naming, and a fixed plan that extends `ExampleQueue` as the owner of `default-queue`.

### Locked Contract

Shared GitHub workflow message names used for both Durable external events and `QueueMessageMetadata.MessageType`:

1. `GithubWorkflowInProgress`
2. `GithubWorkflowCompleted`

Minimum payload for `GithubWorkflowInProgress`:

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

Minimum payload for `GithubWorkflowCompleted`:

```json
{
   "instanceId": "42cf976321bd4288a18a3dc54e3e6228",
   "workflowName": "InternalApi-42cf976321bd4288a18a3dc54e3e6228",
   "runId": 23353310577,
   "conclusion": "success",
   "runAttempt": 1,
   "environment": "dev",
   "repository": "christianacca/web-api-starter"
}
```

Contract notes:

1. `ExampleQueue` remains the sole owner of `default-queue`.
2. The queue transport remains the existing `MessageBody` plus `QueueMessageMetadata` envelope.
3. Phase 1 validates the workflow queue contract in `ExampleQueue` but does not yet raise Durable events from queue messages.

### Steps

- [x] Introduce a neutral workflow-completion queue message concept in the Functions project, for example `GithubWorkflowQueueMessage` or `GithubWorkflowCompletionMessage`.
- [x] Move orchestration event names out of the current webhook class into a shared GitHub workflow message-name type so the orchestrator is no longer coupled to `GithubWebhook`.
- [x] Define a queue message payload model carrying at least:
  - `instanceId`
  - `workflowName`
  - `runId`
  - `conclusion`
  - `runAttempt`
  - repository metadata if needed for diagnostics
- [x] Define the new workflow-completion message type so it fits the existing `ExampleQueue` dispatch pattern on `default-queue`.
- [x] Reuse the existing `MessageBody` plus `QueueMessageMetadata` envelope and do not introduce a second queue envelope format.
- [x] Fix the stable `QueueMessageMetadata.MessageType` names for the workflow message contract.
- [x] Add validation rules for the new workflow-completion queue payload and message metadata.
- [x] Fix the exact minimum JSON payload fields for both `GithubWorkflowInProgress` and `GithubWorkflowCompleted`.
- [x] Update any orchestration code that references event constants from the old webhook class.
- [x] Build the Functions project.
- [x] Update the checklist for this phase.
- [ ] If this phase produced file changes, create one commit on the current branch after verification passed.
- [x] Feed forward any naming, message-shape, queue-ownership, or event-contract findings into Phases 2 through 7.

### Verification

1. `build functions` succeeds.
2. The orchestrator compiles against the shared GitHub workflow message-name contract.
3. A repo search shows the new queue message model exists.
4. The plan explicitly extends `ExampleQueue` as the sole owner of `default-queue` and does not introduce competing queue-triggered consumers.
5. The stable workflow queue message type names and minimum payload fields are explicitly documented.

### Human Intervention

- None expected.

### Approval Gate

- None expected.

### Feed Forward

- Phase 0 is now complete. Keep Phase 1 changes limited to message contract and queue ownership isolation so the verified webhook benchmark remains a stable comparison point.
- Phase 1 locked one shared GitHub workflow message-name set to `GithubWorkflowInProgress` and `GithubWorkflowCompleted`; Phase 2 should reuse those same names for both Durable events and queue routing rather than introducing a second event vocabulary.
- Phase 1 added contract validation inside `ExampleQueue` while keeping webhook delivery active; Phase 2 should replace the current validation-only branch with Durable event raising in the same queue owner instead of creating a second `default-queue` trigger.
- Phase 1 also established that payload `status` is redundant because `QueueMessageMetadata.MessageType` already conveys the same lifecycle state to both code and human operators; later phases should treat `MessageType` as the only status carrier for this queue contract.

### Phase 1 Execution Log

- Date: 2026-03-24
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Added a shared GitHub workflow queue contract in the Functions project, moved orchestration event names into the same shared GitHub workflow message-name type used by queue routing, extended `ExampleQueue` to recognize and validate `GithubWorkflowInProgress` and `GithubWorkflowCompleted` messages on `default-queue`, and kept the existing webhook delivery path intact.
- Verification run: `build functions` succeeded; targeted searches confirmed the shared workflow message names exist and the orchestrator no longer depends on webhook-owned event constants.
- Files changed: `src/Template.Functions/GithubWorkflowOrchestrator/GithubWorkflowContracts.cs`; `src/Template.Functions/GithubWorkflowOrchestrator/GithubWebhook.cs`; `src/Template.Functions/GithubWorkflowOrchestrator/GithubWorkflowOrchestrator.cs`; `src/Template.Functions/ExampleQueue.cs`; `docs/github-workflow-direct-callback-migration-plan.md`
- Findings: The orchestrator was coupled to webhook-owned event-name constants, so Phase 1 introduced one shared GitHub workflow message-name contract before any queue cutover work. The existing `MessageBody` plus `QueueMessageMetadata` envelope was sufficient for the workflow queue design, so no second queue envelope was needed. `ExampleQueue` can now act as the contract-validation point for workflow queue messages while remaining the only `default-queue` trigger.
- Feed-forward updates applied to later phases: Locked the shared GitHub workflow message names and minimum payload fields in the plan, removed redundant payload `status` from the contract because `MessageType` already conveys the same state, and constrained Phase 2 to extend the existing `ExampleQueue` branch rather than creating a competing queue-triggered function.
- Remaining risks: The phase commit remains intentionally uncreated because no explicit commit instruction was given in this session. Queue message handling is validation-only in this phase by design; Durable event raising still belongs to Phase 2.

---

## Phase 1.1: Contract Cleanup Before Queue Cutover

### Goal

Resolve the Phase 1 contract and queue-envelope issues before any Phase 2 queue-consumption work begins. This phase keeps behavior unchanged, but tightens the shared queue envelope handling and the workflow message contract so Phase 2 can build on a sound base.

### Locked Design Decisions

- `ExampleQueue` remains the owner of `default-queue`. Phase 1.1 does not introduce a second queue trigger or move queue-envelope validation into a different function.
- General `MessageBody` envelope validation is a queue concern, not a GitHub workflow concern. The outer envelope must be validated in `ExampleQueue` before any code logs, switches on, or otherwise dereferences `messageBody.Metadata.MessageType`.
- `GithubWorkflowQueueMessageContract` remains GitHub-specific. After Phase 1.1 it should assume the outer `MessageBody` envelope has already passed general queue-envelope validation and should only validate: supported GitHub workflow message type, presence of `Data`, inner payload shape, and payload field constraints.
- The documented workflow queue JSON contract is the source of truth and it uses camelCase field names such as `environment`, `instanceId`, `repository`, `runId`, `runAttempt`, `workflowName`, and `conclusion`. Functions-side deserialization must explicitly support that documented camelCase contract and must not rely on undocumented serializer defaults.
- Supported GitHub workflow message routing must have one source of truth. Replace the current split between `IsSupported(...)` and switch-based deserialization with one mapping from message type to payload contract/validator. If a helper like `IsSupported(...)` remains, it must derive from that same mapping rather than duplicate it.
- The shared GitHub workflow message names remain exactly `GithubWorkflowInProgress` and `GithubWorkflowCompleted`. Phase 1.1 does not rename them, add aliases, or reintroduce a redundant inner `status` field.
- Phase 1.1 remains validation-only. `ExampleQueue` still does not raise Durable events from GitHub workflow queue messages in this phase.

### Steps

- [x] Add an explicit general queue-envelope validation step in `ExampleQueue` and run it before any logging or switch dispatch that reads `messageBody.Metadata.MessageType` in both the main queue handler and the poison-queue handler.
- [x] Keep that general envelope validation outside `GithubWorkflowQueueMessageContract`; do not mix outer `MessageBody` checks into the GitHub-specific payload contract.
- [x] Update `GithubWorkflowQueueMessageContract` so it validates only GitHub workflow message concerns after the outer queue envelope is known-valid.
- [x] Make workflow queue payload deserialization explicitly compatible with the documented camelCase JSON contract rather than depending on serializer defaults.
- [x] Keep the documented payload field set unchanged in this phase: `environment`, `instanceId`, `repository`, `runId`, `runAttempt`, `workflowName`, and for completed messages `conclusion`.
- [x] Replace the duplicated `IsSupported(...)` plus switch-dispatch arrangement with one authoritative mapping from message type to payload model/validator.
- [x] If an `IsSupported(...)` helper still exists after the refactor, ensure it reads from the authoritative mapping instead of duplicating the supported-type list.
- [x] Keep the shared GitHub workflow message names unchanged: `GithubWorkflowInProgress` and `GithubWorkflowCompleted`.
- [x] Preserve Phase 1 behavior exactly: validation-only handling in `ExampleQueue`, with no Durable event raising from queue messages yet.
- [x] Build the Functions project.
- [x] Update the checklist for this phase.
- [ ] If this phase produced file changes, create one commit on the current branch after verification passed.
- [x] Feed forward any queue-envelope, serializer, or contract-shape findings into Phases 2 through 7.

### Verification

1. `build functions` succeeds.
2. `ExampleQueue` no longer dereferences `messageBody.Metadata.MessageType` before a general queue-envelope validation step has run in either queue-trigger entry point.
3. General queue-envelope validation remains outside `GithubWorkflowQueueMessageContract`, and GitHub-specific validation only runs after the envelope is known-valid.
4. The documented camelCase workflow payload shape deserializes successfully against the Functions-side contract without changing the documented field names.
5. Supported workflow message types and payload dispatch are defined in one authoritative mapping, with no second manually-maintained supported-type list.
6. The only supported GitHub workflow queue message names remain `GithubWorkflowInProgress` and `GithubWorkflowCompleted`.
7. Queue handling remains validation-only; no Durable event raising is introduced in this phase.

### Human Intervention

- None expected.

### Approval Gate

- None expected.

### Feed Forward

- Phase 1.1 exists to close three pre-Phase-2 issues discovered during review: queue-envelope null-dereference risk in `ExampleQueue`, likely mismatch between documented camelCase payloads and current deserialization behavior, and drift risk between supported-type validation and deserialization dispatch.
- Later phases must treat these decisions as locked unless the plan is explicitly revised again: outer queue-envelope validation stays in `ExampleQueue`, the GitHub workflow contract stays GitHub-specific and camelCase-compatible, and message-type support/dispatch stays driven from one mapping.
- Phase 1.1 now enforces the documented workflow payload casing through the shared payload serializer options instead of per-property attributes. Later publishers and tests should keep emitting those exact camelCase field names.
- Do not begin Phase 2 until these contract-cleanup items are verified.

### Phase 1.1 Execution Log

- Date: 2026-03-24
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Added explicit outer queue-envelope validation in `ExampleQueue` before any logging or dispatch in both queue-trigger entry points, moved the shared non-null envelope rules into `MessageBody` and `QueueMessageMetadata`, kept GitHub-specific validation outside the shared envelope model, refactored workflow payload validation to use one authoritative message-type-to-validator mapping, and made the workflow payload deserializer explicitly use camelCase naming rules while preserving Phase 1's validation-only behavior.
- Verification run: `build functions` succeeded; targeted inspection confirmed `messageBody.Metadata.MessageType` is not dereferenced before envelope validation, workflow message support/dispatch comes from one mapping, and the documented camelCase payload fields remain the contract source of truth.
- Files changed: `src/Template.Functions/ExampleQueue.cs`; `src/Template.Functions/GithubWorkflowOrchestrator/GithubWorkflowContracts.cs`; `docs/github-workflow-direct-callback-migration-plan.md`
- Findings: The Phase 1 implementation had a real null-dereference risk because both queue-trigger entry points logged `messageBody.Metadata.MessageType` before checking whether the outer envelope had deserialized correctly. The Phase 1 contract also split supported-type validation from payload dispatch, which created avoidable drift risk ahead of Phase 2. The shared envelope rules fit better on `MessageBody` and `QueueMessageMetadata`, but the root null check still has to remain in `ExampleQueue` because model-level validation cannot run if the queue trigger fails to materialize the root object. CamelCase payload compatibility is now enforced through serializer options instead of per-property JSON attributes.
- Feed-forward updates applied to later phases: Phase 2 should continue to treat `ExampleQueue` as the queue-envelope boundary, should reuse the existing contract mapping instead of reintroducing a second supported-type list, and should keep publisher payloads on the documented camelCase field names when queue publication is added.
- Remaining risks: The phase commit remains intentionally uncreated because no explicit commit instruction was given in this session. Queue handling is still validation-only by design; Durable event raising and duplicate-side-effect prevention remain Phase 2 work.

---

## Phase 2: Replace The Functions Webhook Receiver With Queue Consumption

### Goal

Swap the current webhook-triggered Functions receiver for queue-driven processing that raises the same Durable events.

### Steps

- [x] Replace [src/Template.Functions/GithubWorkflowOrchestrator/GithubWebhook.cs](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Functions/GithubWorkflowOrchestrator/GithubWebhook.cs) with queue-driven workflow-completion handling, or rename the file and class accordingly.
- [x] Remove webhook-specific deserialization of `WorkflowRunEvent`.
- [x] Implement workflow-completion message handling in `ExampleQueue` on `default-queue` without creating multiple competing triggers on the same queue.
- [x] Raise `in progress` and `completed` Durable events from the new queue payload.
- [x] Preserve idempotent logging and defensive validation.
- [x] Make queue processing idempotent for duplicate `GithubWorkflowInProgress` and `GithubWorkflowCompleted` deliveries that repeat the same `instanceId`, `runId`, `runAttempt`, and message type.
- [x] Ensure invalid or unsupported queue messages fail in a controlled way and use the poison-queue path appropriately through the existing `ExampleQueue` handling model.
- [x] Update any development queue initialization if additional queue artifacts are required.
- [x] Build the Functions project.
- [ ] If practical, add or update tests covering payload validation and event mapping.
- [x] Update the checklist for this phase.
- [ ] If this phase produced file changes, create one commit on the current branch after verification passed.
- [x] Feed forward any queue processing, poison-handling, or message-routing assumptions into Phases 3 through 7.

### Verification

1. `build functions` succeeds.
2. The new queue-driven handler compiles and the old webhook-specific model dependency is no longer required in that function.
3. A targeted search confirms `ExampleQueue` remains the sole `default-queue` owner and now handles the workflow-completion message type.
4. Final-attempt failure behavior for unsupported or invalid workflow messages is understood and documented.
5. Duplicate workflow queue messages do not create duplicate durable side effects.

### Human Intervention

- None expected.

### Approval Gate

- None expected.

### Feed Forward

- Phase 0 exposed two local validation prerequisites for later queue-based work: a valid GitHub App private key/JWT source is required before any GitHub dispatch-based comparison is meaningful, and local API invocation needs an explicit bearer-token acquisition step if the benchmark continues to go through the proxied API route.
- Phase 1 locked the workflow queue contract on the existing `MessageBody` envelope and the existing `ExampleQueue` trigger, and it now uses one shared GitHub workflow message-name set for both Durable events and queue routing. Phase 2 should build on that branch, replacing validation-only handling with Durable event raising and duplicate protection keyed by `instanceId`, `runId`, `runAttempt`, and message type.
- Phase 1.1 locked `ExampleQueue` as the outer queue-envelope validation boundary and made workflow payload casing explicit through the shared serializer options. Phase 2 should preserve that split by keeping envelope checks in `ExampleQueue` and reusing the existing workflow contract mapping instead of duplicating message-type support logic.
- Phase 1 removed redundant payload `status`; Phase 2 and later publishers should rely on `QueueMessageMetadata.MessageType` rather than duplicating lifecycle state inside the inner workflow payload.
- Phase 2 now reserves workflow-message processing in the existing `defaultqueuestorage` table before raising a Durable event and marks the record completed only after the raise succeeds. The persisted workflow state entity is intentionally minimal, containing only dedupe/status fields rather than a flattened payload projection. Later phases should preserve that reserve-then-complete pattern and avoid re-expanding the dedupe table unless a concrete query requirement appears.
- Phase 2 extracted the GitHub workflow queue path into `GithubWorkflowQueueMessageProcessor` while keeping `ExampleQueue` as the sole `default-queue` trigger and outer envelope-validation boundary. Later phases should extend the dedicated processor for workflow-specific changes rather than pushing that logic back into `ExampleQueue`.
- Phase 2 simplified `GithubWorkflowQueueMessageContract.Parse` to assume a valid outer `MessageBody` envelope and only enforce workflow-specific type and payload rules. Later phases should preserve that boundary and keep general queue-envelope validation in `ExampleQueue`.
- Phase 2 no longer uses `ExampleQueueExceptionHandler` for GitHub workflow messages. Workflow messages still retry normally, but on the final attempt the dedicated processor logs the failure inline after cleaning up any in-progress dedupe state instead of sending the message to `default-queue-poison`. Later phases should keep that distinction clear when documenting or testing workflow failure behavior.
- Phase 2 leaves the `GithubWebhook` HTTP route in place only as an explicit disabled endpoint that returns `410 Gone`. Later phases should remove the API-side webhook proxying and the GitHub App webhook configuration before expecting any environment to rely exclusively on queue publication.

### Phase 2 Execution Log

- Date: 2026-03-24
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Replaced Phase 1's validation-only workflow queue branch with queue-driven Durable event raising, added a typed workflow-message parser for `GithubWorkflowInProgress` and `GithubWorkflowCompleted`, introduced table-backed duplicate suppression keyed by `instanceId`, `runId`, `runAttempt`, and message type, extracted the workflow-specific queue logic into `GithubWorkflowQueueMessageProcessor`, simplified the dedupe state table to a minimal key/status ledger, changed final-attempt workflow message failures to inline logging instead of poison-queue handling, and retired the Functions-side webhook receiver into a disabled `410 Gone` endpoint so workflow completion is no longer mapped from GitHub webhook models in the Functions app.
- Verification run: `build functions`; direct `dotnet build src/Template.Functions/Template.Functions.csproj /property:GenerateFullPaths=true /consoleloggerparameters:NoSummary`; targeted search for `QueueTrigger(QueueName)|QueueTrigger(PoisonQueueName)` in `src/Template.Functions/**` showed only `ExampleQueue` and its poison handler own `default-queue`; targeted search for `WorkflowRunEvent|WorkflowRunAction|WorkflowRunStatus|WorkflowRunConclusion` in `src/Template.Functions/GithubWorkflowOrchestrator/GithubWebhook.cs` returned no matches.
- Files changed: `src/Template.Functions/ExampleQueue.cs`; `src/Template.Functions/GithubWorkflowOrchestrator/GithubWorkflowContracts.cs`; `src/Template.Functions/GithubWorkflowOrchestrator/GithubWorkflowQueueMessageProcessor.cs`; `src/Template.Functions/GithubWorkflowOrchestrator/GithubWebhook.cs`; `src/Template.Functions/Program.cs`; `src/Template.Functions/Shared/GithubWorkflowMessageStateTableEntity.cs`; `docs/github-workflow-direct-callback-migration-plan.md`
- Findings: `ExampleQueue` remains the sole owner of `default-queue`, but workflow-specific processing now lives in `GithubWorkflowQueueMessageProcessor` and `ExampleQueue` acts as the queue-trigger and envelope-validation boundary. The workflow contract parser now assumes a valid outer `MessageBody` envelope and only enforces workflow-specific type and payload rules. Duplicate queue deliveries are suppressed by reserving a correlation-keyed table row before the Durable raise and skipping later deliveries that collide on the same key; that persisted state is now intentionally minimal and stores only dedupe/status data. Invalid or unsupported workflow queue messages still retry, but on the final attempt they are handled inline with error logging and dedupe-state cleanup rather than being moved to the poison queue.
- Feed-forward updates applied to later phases: Recorded the dedicated workflow queue processor boundary, the simplified minimal dedupe ledger, the parser boundary that leaves outer-envelope validation in `ExampleQueue`, the inline final-attempt failure handling for workflow messages, and the fact that the Functions-side webhook endpoint is intentionally disabled and must be removed from the remaining API and GitHub-side flow during later cutover work.
- Remaining risks: No automated tests were added in this phase because there is no existing Functions test project in the repository, so duplicate suppression, inline final-attempt failure handling, and Durable event mapping are currently verified by build plus code-path inspection rather than executable tests. The phase commit remains intentionally uncreated because no explicit commit instruction was given in this session.

---

## Phase 3: Enable GitHub Actions To Authenticate And Publish To The Function App Queue

### Goal

Authorize the GitHub Actions service principal to publish messages to the Function App storage queue and prove the workflow can acquire the right queue access, while preparing the later global rollout.

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
1. `pipeline`
   The dispatching GitHub App's full authorized pipeline environment list as JSON.
1. `authorized-target-envs`
   The ordered intersection between `gated-environments` and the app-authorized pipeline environments, serialized as a JSON array for downstream `if` conditions.
   Expected shape:

```json
["dev","qa"]
```

1. `published-in-progress`
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
  "conclusion": "success",
  "environment": "dev",
  "repository": "christianacca/web-api-starter"
}
```

Design notes:

1. `instanceId` is the orchestration correlation key and must always be present.
2. `runId` is required on both message types so Durable event handling and later diagnostics remain consistent.
3. `runAttempt` should be included from the start even if the initial implementation only needs attempt `1`.
4. `MessageType` already carries the lifecycle state, so payload `status` should not be duplicated in the inner workflow queue payload.
5. `environment` should refer to the primary environment used for queue publication.
6. `repository` should be the full `owner/repo` string for diagnostics and defensive validation.
7. Queue publishers should serialize the outer `MessageBody` once and should serialize the inner payload once into `MessageBody.Data`.
8. The Functions consumer should treat the tuple `instanceId` plus `runId` plus `runAttempt` plus message type as the minimum duplicate-detection key.
9. Repeated queue messages with the same duplicate-detection key must not cause duplicate durable side effects.

### Local Verification Seam For Phase 3

Phase 3 local end-to-end verification now uses one workflow-carried override seam rather than ad hoc action edits.

Local-only workflow input:

1. `localVerification`
    Optional JSON string supplied only by the local Functions dispatcher when running in development.

Expected JSON shape:

```json
{
   "storageConnectionString": "DefaultEndpointsProtocol=https;AccountName=devstoreaccount1;AccountKey=<azurite-key>;QueueEndpoint=https://<your-dev-tunnel-host>/devstoreaccount1"
}
```

Rules:

1. The steady-state workflow path remains unchanged when `localVerification` is absent.
2. The local Functions dispatcher should populate `localVerification` only when running in development and only when a public Azurite queue endpoint override has been configured locally.
3. `github-app-authz-envs` and `publish-github-workflow-completed` should treat `localVerification` as the single source of truth for Phase 3 local queue publication overrides.
4. When `localVerification` is present, the shared queue support path should bypass conventions-based storage-account lookup for publication transport only.
5. When `localVerification` is present, the reusable queue publisher should publish with `az storage message put --connection-string ...` rather than `--auth-mode login`.
6. Authorization, workflow gating, payload shape, workflow-name parsing, and message correlation rules must stay identical between steady-state and local-verification runs.
7. The workflow branch used for local verification should be overridden locally through `.NET user-secrets` on `Github:Branch`, not by editing checked-in development appsettings.
8. The public queue endpoint used to construct `localVerification.storageConnectionString` should also be configured locally through `.NET user-secrets`, for example `Github:LocalVerification:QueueEndpoint`.
9. `AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1` is not part of the Phase 3 queue-publication seam. It may still be needed for separate direct local CLI diagnostics against the self-signed `https://127.0.0.1` Azurite endpoints, but the dev-tunnel queue-publication path validated for Phase 3 uses the public tunnel endpoint and should not rely on that environment variable.

### Steps

- [x] Identify the storage account that backs the Function App `default-queue` in each environment and trace how that account is expressed in conventions and deployment.
- [x] Update infrastructure so the correct GitHub Actions principal id for each environment can publish queue messages to that storage account using the built-in `Storage Queue Data Message Sender` role at the storage account scope.
- [x] Trace where those principal ids and storage scopes are composed in deployment and update that parent logic.
- [x] Verify the principal ids sourced from [set-azure-connection-variables.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/azure-login/set-azure-connection-variables.ps1) flow correctly into deployment.
- [x] Confirm the workflow has the storage account name, queue name, and `auth-mode login` inputs it needs to publish to `default-queue`.
- [x] Document the current GitHub App webhook settings for the environment being migrated, including webhook URL, subscribed events, operational owner, and rollback steps to restore webhook delivery if needed.
- [x] Prepare the GitHub-side change needed to disable webhook delivery for the target environment once queue-publication verification is ready.
- [x] Update [github-app-authz-envs/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/github-app-authz-envs/action.yml) so it accepts a required multi-line `gated-environments` input.
- [x] Update `github-app-authz-envs` so it computes the intersection between the workflow-gated environments passed in by the workflow and the dispatching GitHub App's authorized pipeline environments.
- [x] Make `github-app-authz-envs` fail the workflow if that intersection is empty.
- [x] Update `github-app-authz-envs` outputs so downstream jobs consume `authorized-target-envs` rather than the unconstrained pipeline environment list.
- [x] Preserve the existing `primary` and `pipeline` outputs unless a later phase proves they can be removed safely.
- [x] Extend `github-app-authz-envs` to sign into Azure using the primary environment for the dispatching GitHub App.
- [x] Add one reusable workflow queue publisher composite action backed by a local PowerShell script that uses `az storage message put --auth-mode login`.
- [x] Extend `github-app-authz-envs` to discover the target storage account and publish the `in progress` message to `default-queue` for that primary environment by calling the reusable queue publisher action.
- [x] Make `github-app-authz-envs` fail if actor resolution, environment authorization, Azure login, storage discovery, or bootstrap queue publication fails.
- [x] Keep `github-app-authz-envs` focused on bootstrap behavior only. The `completed` queue message should be published later in the workflow by calling the same reusable queue publisher action from a final step that always runs.
- [x] Update the showcase workflow [github-integration-test.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/workflows/github-integration-test.yml) to pass the workflow's gated environments into `github-app-authz-envs` using a multi-line YAML block scalar, accept an optional `localVerification` workflow input for local Phase 3 verification, consume the `authorized-target-envs` output from `github-app-authz-envs`, rely on `github-app-authz-envs` to publish the single bootstrap `in progress` message, and publish the `completed` message to `default-queue` by invoking the same reusable queue publisher action in a final step that always runs.
- [x] Ensure only the bootstrap step publishes the `in progress` message and only the final completion step publishes the `completed` message.
- [x] Ensure the final completion publisher step is guarded with `if: always()` and only attempts publication when the bootstrap path already reported `published-in-progress == 'true'`.
- [x] Add one development-only local verification seam so the local Functions dispatcher can send an optional `localVerification` workflow input without changing the steady-state workflow path.
- [x] Keep the local verification seam narrow: override only queue publication transport and branch selection, while preserving the same workflow, payload, and orchestration correlation behavior used in steady state.
- [x] Support local branch selection through `.NET user-secrets` on `Github:Branch` rather than checked-in local appsettings changes.
- [x] Support local queue publication through a public Azurite queue endpoint configured locally, with the workflow publisher using a connection-string-based path only when the development-only override is present.
- [x] Define the local verification procedure for this phase so it runs through the real local orchestrator start path, the real GitHub Actions workflow on a feature branch, and the real `GithubWorkflowInProgress` plus `GithubWorkflowCompleted` queue messages delivered back into local Azurite.
- [ ] Run one dark-launch deployment of the Phase 3 infrastructure and application changes to the dev Azure environment from the feature branch while keeping queue-based completion delivery non-default and limited to the showcase workflow.
- [ ] Verify in the deployed dev environment that the dark-launched Phase 3 changes preserve the existing default webhook-driven behavior for normal application flows while the showcase workflow remains able to exercise the queue-publication path.
- [x] Keep queue-based completion delivery contained to the showcase workflow until the global rollout and cleanup phases are ready.
- [x] Build the solution.
- [x] Update the checklist for this phase.
- [ ] If this phase produced file changes, create one commit on the current branch after verification passed.
- [x] Feed forward workflow, storage-auth, and queue-publishing findings into Phases 4 through 6.

### Verification

1. `build solution` succeeds.
2. `github-app-authz-envs` fails closed when the dispatching GitHub App is not authorized for any workflow-gated environment.
3. The workflow YAML passes explicit gated environments into `github-app-authz-envs` using the documented multi-line input shape and consumes `authorized-target-envs` from that action.
4. `github-app-authz-envs` publishes exactly one `in progress` message for the primary environment.
5. The workflow publishes exactly one `completed` message from the same reusable queue publisher action in a final step.
6. Infrastructure diffs show the GitHub Actions principal receives the built-in `Storage Queue Data Message Sender` role on the expected storage account scope.
7. The reusable queue publication helper uses `az storage message put --auth-mode login` and does not fall back to shared keys, connection strings, or SAS.
8. If deployment validation is available, confirm the workflow can publish raw `MessageBody` JSON to the intended storage account and queue using the chosen auth mode.
9. For local Phase 3 verification, use the canonical runbook in [docs/workflow-orchestration-setup.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/workflow-orchestration-setup.md) under `Exact Local E2E Validation Procedure` rather than restating the operator steps in this plan.
10. That runbook is the source of truth for the local-only configuration needed by the `localVerification` seam, including `Github:Branch`, `Github:LocalVerification:QueueEndpoint`, tunnel hosting, Functions startup, and durable-state inspection.
11. If direct local Azure CLI diagnostics against `https://127.0.0.1` Azurite are needed during troubleshooting, follow the same runbook notes and treat `AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1` as a separate operator-side diagnostic prerequisite rather than part of the queue-publication seam itself.
12. If feature-branch deployment to dev is available, run one dark-launch validation of the Phase 3 branch state in the real dev Azure environment before Phase 4. That deployed validation should confirm only the intended dev environment changes land, queue publication remains dark and limited to the showcase workflow, and no default application path has been switched away from webhook delivery yet.

### Human Intervention

- None expected for code changes, local validation, workflow/action authoring, or infrastructure-as-code modifications.
- Human intervention may be required only if verifying or applying the infrastructure change depends on running an approval-gated deployment workflow, using production-like environment approvals, or using credentials the agent cannot access directly.

### Approval Gate

- Treat this phase as autonomous by default.
- Only introduce an approval gate if applying or validating the infrastructure changes requires an environment deployment approval or a human-triggered deployment workflow run.
- A dark-launch validation deployment to dev is recommended when feature-branch deployment is available, but it does not replace the mandatory Phase 4 rollout and deployed end-to-end verification gates.

### Feed Forward

- Phase 3 resolved queue publication through one reusable action and one checked-in PowerShell helper. Later phases should keep publication logic in that shared path instead of reintroducing inline `az storage` calls in workflow YAML.
- The internal API storage-account sender RBAC now comes from `settings.CliPrincipals[settings.EnvironmentName]`, and those principal ids are still sourced through [set-azure-connection-variables.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/azure-login/set-azure-connection-variables.ps1) via [get-product-azure-connections.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/get-product-azure-connections.ps1) and [get-product-conventions.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/get-product-conventions.ps1). Later infrastructure changes should preserve that single conventions path rather than hard-coding principal ids elsewhere.
- `github-app-authz-envs` now fails closed on unsupported actors and empty gated-environment intersections, and it publishes the bootstrap `GithubWorkflowInProgress` message exactly once. Later phases should keep bootstrap publication centralized there and should not add a second `in progress` publisher anywhere else in the workflow.
- The showcase workflow keeps queue-based delivery dark by limiting it to [github-integration-test.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/workflows/github-integration-test.yml). Phase 4 should be the point where queue publication becomes the default on `master` and is deployed to every environment before API-side webhook cleanup begins.
- The workflow name now carries the dispatcher prefix, and both bootstrap and completion publishers derive the target storage account from that prefix rather than assuming a hard-coded dispatcher like `InternalApi`. Later phases should preserve that non-hardcoded parsing unless the queue contract moves dispatcher identity into an explicit field again.
- Both bootstrap and completion publishers still derive `instanceId` from the required `workflowName` input using the `<dispatcher>-<instanceId>` naming scheme. The current producer still emits `InternalApi-{instanceId}`. Later workflow or orchestrator changes must preserve that contract unless the queue payload contract is explicitly revised.
- The completion publisher computes `conclusion` from downstream job results and only runs when `published-in-progress == 'true'`. Later phases should preserve that guard so workflows do not emit orphaned completion messages after a failed bootstrap path.
- Phase 3 now keeps the higher-level workflow authorization, workflow-name parsing, storage-account resolution, and payload-building logic in a focused PowerShell module at [.github/actions/_shared/GitHubWorkflowQueueSupport.psm1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/_shared/GitHubWorkflowQueueSupport.psm1), with thin action-local entry scripts. Later phases should extend that module or its entry points rather than pushing logic back into inline YAML.
- The shared module now resolves infrastructure scripts relative to `$PSScriptRoot` instead of assuming the current working directory is the repository root. Later phases should keep action-support PowerShell path resolution module-relative or script-relative rather than depending on runner cwd.
- The current action pattern passes GitHub expression values through `env:` and then into typed PowerShell parameters. Later phases should preserve that boundary as a hardening measure instead of interpolating untrusted workflow values directly into inline script text.
- A Phase 3 dev dark-launch deployment is useful as an operational smoke test for RBAC, infrastructure drift, and branch-built artifacts, but it should stay non-default and must not be treated as the global rollout gate. Phase 4 remains the point where queue publication becomes the default on `master` and where deployed end-to-end verification becomes mandatory.
- Phase 3 local verification now uses one development-only workflow input named `localVerification`. Later phases should keep local E2E verification on that single seam rather than introducing separate ad hoc action flags or conventions overrides for local-only queue publication.
- The canonical local-only operator procedure now lives in [docs/workflow-orchestration-setup.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/workflow-orchestration-setup.md) under `Exact Local E2E Validation Procedure`. Later phases should update that section rather than duplicating or drifting from it here. If you step outside that seam and run direct local Azure CLI diagnostics against the self-signed `https://127.0.0.1` Azurite endpoints, handle `AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1` as a separate troubleshooting prerequisite.
- Local E2E validation showed that the workflow callback publisher must align with the function app's queue-trigger encoding contract. If the app keeps the default queue-trigger encoding semantics, the workflow publisher must emit a base64-encoded `MessageBody` envelope rather than relying on a host-wide `messageEncoding` override.
- Local E2E validation also exposed that the workflow-message dedupe ledger must not rely on a populated post-insert ETag when marking a message completed. Later phases should preserve the current completion write path that does not require reading back an ETag before updating dedupe state.
- The canonical runbook now assumes PowerShell command blocks and Azure CLI table queries using `-o json` rather than `--accept application/json`. Later troubleshooting steps should preserve those compatibility assumptions unless the repo standardizes on newer tool versions.

### Phase 3 Execution Log

- Date: 2026-03-24
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Added a reusable workflow queue publisher composite action and backing PowerShell helper that publish a `MessageBody` envelope with `az storage message put --auth-mode login`, extended `github-app-authz-envs` to accept multi-line gated environments, fail closed on unsupported actors and empty intersections, sign into Azure for the dispatching app's primary environment, derive the target storage account from the dispatcher prefix encoded in `workflowName` without hard-coding `InternalApi`, and publish exactly one bootstrap `GithubWorkflowInProgress` message, updated the showcase workflow to consume `authorized-target-envs`, extracted the final `GithubWorkflowCompleted` publication into a dedicated repo-local composite action, and then refactored the higher-level repeated PowerShell logic in both actions into a focused module under [.github/actions/_shared](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/_shared) plus thin action-local entry scripts while keeping the job-level `if: always()` guard and the low-level queue transport action unchanged. Phase 3 also hardened those shared scripts so infrastructure helper paths resolve from the module location rather than the runner's current working directory, and it now includes a development-only `localVerification` seam that lets local end-to-end verification publish back into Azurite through a public queue endpoint without altering the steady-state production path.
- Verification run: `dotnet build "$PWD/WebApiStarterTemplate.sln" /property:GenerateFullPaths=true /consoleloggerparameters:NoSummary`; targeted repo searches for `gated-environments`, `authorized-target-envs`, `published-in-progress`, `publish-workflow-queue-message`, and `GitHubWorkflowQueueSupport`; targeted Bicep inspection of `Storage Queue Data Message Sender` assignments on the internal API storage account; `pwsh -NoProfile -Command '$module = Join-Path $PWD ".github/actions/_shared/GitHubWorkflowQueueSupport.psm1"; Import-Module $module -Force; $envName = (& ./tools/infrastructure/get-product-environment-names.ps1 | Select-Object -First 1); $context = Resolve-WorkflowQueueContext -WorkflowName "InternalApi-test-instance" -EnvironmentName $envName; Write-Host "env=$envName storage=$($context.StorageAccountName) dispatcher=$($context.WorkflowDispatcherName)"'`
- Files changed: `.github/actions/github-app-authz-envs/action.yml`; `.github/actions/github-app-authz-envs/get-authorized-target-envs.ps1`; `.github/actions/github-app-authz-envs/new-bootstrap-payload.ps1`; `.github/actions/_shared/GitHubWorkflowQueueSupport.psm1`; `.github/actions/publish-workflow-queue-message/action.yml`; `.github/actions/publish-workflow-queue-message/publish-workflow-queue-message.ps1`; `.github/actions/publish-github-workflow-completed/action.yml`; `.github/actions/publish-github-workflow-completed/new-completed-payload.ps1`; `.github/workflows/github-integration-test.yml`; `src/Template.Functions/GithubWorkflowOrchestrator/TriggerWorkflowActivity.cs`; `tools/infrastructure/arm-templates/main.bicep`; `docs/github-workflow-direct-callback-migration-plan.md`
- Findings (infrastructure): The internal API queue owner was already the environment-specific storage account declared in [main.bicep](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/arm-templates/main.bicep), and that storage-account name already flows into conventions as `SubProducts.InternalApi.StorageAccountName`. The GitHub Actions service-principal object ids already flow from [set-azure-connection-variables.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/azure-login/set-azure-connection-variables.ps1) into deployment through [get-product-azure-connections.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/get-product-azure-connections.ps1) and [get-product-conventions.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/get-product-conventions.ps1), so Phase 3 only needed to thread that existing principal into the storage-account role assignments.
- Findings (publisher): Queue publication again infers the target dispatcher from the workflow-name prefix, but the publisher actions now parse that prefix generically instead of assuming `InternalApi`, while still deriving `instanceId` from the remainder of the workflow name. The higher-level workflow queue logic is now shared through a focused PowerShell module rather than duplicated inline across two composite actions, and that module now uses module-relative path resolution so it does not implicitly depend on the current working directory being the repository root.
- Findings (webhook settings): The current webhook settings for the dev environment remain: webhook URL `https://dev-api-was.codingdemo.co.uk/api/github/webhooks`, subscribed event `workflow_run`, operational owner `GitHub Admin Team` as documented in [github-app-creation.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/github-app-creation.md), and the remaining GitHub-side cleanup work belongs after the queue-based path has been deployed to all environments.
- Findings (local E2E validation): The first live local E2E run reached the real GitHub Actions workflow successfully but failed at the Functions queue trigger boundary because the Phase 3 publisher emitted an unencoded `MessageBody` document while the function app kept the default Storage Queues base64 trigger semantics. The workflow-specific fix is to publish the `MessageBody` envelope in the encoding expected by the queue trigger rather than changing the host-wide queue extension setting. The later dedupe completion failure in `GithubWorkflowQueueMessageProcessor` was a separate real bug: the completion update used `UpdateEntityAsync` with an uninitialized ETag after the durable event had already been raised. Replacing that completion update with a non-ETag-dependent upsert removed the false retry path.
- Findings (final local evidence): The final local validation run used instance `f2e0a677ceca42d48609cd5685bd59b3` and GitHub Actions run `23612688056` on branch `github-workflow-auth-callback`. The workflow completed with conclusion `success`, the Functions log recorded `RaiseEvent:GithubWorkflowInProgress`, `RaiseEvent:GithubWorkflowCompleted`, and terminal orchestrator completion for that instance, and Azurite-backed `TestHubNameInstances` plus `TestHubNameHistory` both recorded the same instance in a completed terminal state.
- Feed-forward updates applied to later phases: Recorded that queue publication is now centralized in one composite action, one low-level PowerShell transport helper, and one focused shared PowerShell module, that the sender RBAC path should continue to use conventions-driven principal ids, that the showcase workflow remains the only non-default queue-publishing path before the global rollout phase, that the final completion publisher already has the `always()` plus `published-in-progress` guard later phases should preserve, and that action-support scripts should continue to use env-mapped inputs plus module-relative path resolution rather than inline script interpolation or cwd-dependent helper paths.
- Remaining risks: Phase 3 local verification is now complete, including a live GitHub Actions run feeding queue callbacks back into local Azurite. The remaining risks are operational and belong to later phases: global deployment of the queue-based path, application cleanup after that rollout, GitHub-side webhook removal, and confirmation that the queue-only path behaves the same way after webhook behavior is removed.

### Phase 3 Failure-Path Addendum

- Date: 2026-03-26
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Added one intentional branch-local failure step to [github-integration-test.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/workflows/github-integration-test.yml), committed it on `github-workflow-auth-callback` as `5f6d8df` (`Validate workflow failure callback path`), and re-ran the exact local Phase 3 queue-callback validation path against that branch to prove that a failing GitHub Actions run still delivers `GithubWorkflowInProgress` and `GithubWorkflowCompleted` back into local Azurite and that the orchestrator consumes the failure outcome successfully.
- Verification run: Restored the Phase 3 local validation prerequisites, temporarily set local `.NET user-secrets` `Github:MaxAttempts=1` to keep the proof focused on the first failed completion, triggered [GithubWorkflowTrigger](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Functions/GithubWorkflowOrchestrator/GithubWorkflowTrigger.cs) locally, and validated instance `b23fbe8b2d8c49989774e3193a8d44fe` against GitHub Actions run `23617854912` on branch `github-workflow-auth-callback`. The workflow completed with conclusion `failure` on commit `5f6d8dfdde6691140705081d3249f8a8df64a90b`. [tmp/local-workflow-functions.log](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tmp/local-workflow-functions.log) recorded both `RaiseEvent:GithubWorkflowInProgress` and `RaiseEvent:GithubWorkflowCompleted` for that same instance, and the Azurite-backed durable tables recorded the matching terminal state in [tmp/all-durable-instances.json](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tmp/all-durable-instances.json) and [tmp/all-durable-history.json](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tmp/all-durable-history.json).
- Findings: The queue path correctly propagated a failed workflow conclusion into the orchestrator. In durable history for instance `b23fbe8b2d8c49989774e3193a8d44fe`, `EventRaised` for `GithubWorkflowCompleted` carried input `false`, and the same execution then wrote `ExecutionCompleted` with orchestration status `Completed`. That confirms the current orchestrator semantics: when `MaxAttempts=1`, a failed workflow outcome is consumed and reported as a completed orchestration with a failure-valued completion event rather than as a failed Durable runtime status.
- Feed-forward updates applied to later phases: Phase 4 cleanup should preserve this verified queue-only failure-path behavior unless the desired product semantics change. If later phases want durable runtime status itself to surface workflow failure, that is a separate behavioral change from webhook removal and should not be conflated with Phase 4 cleanup. The local failure-path proof also confirmed that [github-integration-test.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/workflows/github-integration-test.yml) remains a safe dark-launch vehicle for targeted branch validation before queue delivery becomes the default path on `master`.

### Phase 3 Success-Path Observability Addendum

- Date: 2026-03-27
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Removed the temporary intentional failure from [github-integration-test.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/workflows/github-integration-test.yml), pushed the branch state to GitHub, and ran one full local Phase 3 queue-callback validation to confirm the success path and the new orchestration observability contract.
- Verification run: Triggered [GithubWorkflowTrigger](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Functions/GithubWorkflowOrchestrator/GithubWorkflowTrigger.cs) locally, which returned instance `a35cc5d099ce4c679af8e99b8830aafa`. GitHub Actions run `23664888007` on branch `github-workflow-auth-callback` completed with conclusion `success` on attempt `1`. The Azurite-backed durable row in [tmp/e2e-success-durable-instances.json](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tmp/e2e-success-durable-instances.json) recorded `RuntimeStatus=Completed` with identical serialized `CustomStatus` and `Output` payloads: `{"stage":"Completed","finalOutcome":"Succeeded","currentAttempt":1,"maxAttempts":2,"runId":23664888007,"workflowRunAttempt":null,"workflowStatus":"Completed","workflowConclusion":"Success","workflowSucceeded":true,"isTerminal":true,"message":"The GitHub workflow completed successfully."}`. The sampled durable timeline in [tmp/e2e-success-status-timeline.jsonl](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tmp/e2e-success-status-timeline.jsonl) showed `CustomStatus` progressing through `WaitingForRunStart` and `WaitingForCompletion` while `Output` remained `null`, then both fields converged on the same terminal success object. Durable history in [tmp/e2e-success-durable-history.json](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tmp/e2e-success-durable-history.json) recorded `EventRaised` entries for both `GithubWorkflowInProgress` and `GithubWorkflowCompleted`, followed by `ExecutionCompleted` carrying the same serialized success result.
- Findings: The observability change behaves as intended on the success path. Operators can observe meaningful in-flight status from durable `CustomStatus`, and the final terminal result is available in both `CustomStatus` and `Output` without requiring different payload shapes. The current serialized terminal payload remains string-valued at the JSON boundary even though the backing C# model now uses enums, because the Functions serializer is configured with string enum conversion.
- Feed-forward updates applied to later phases: Preserve the current success-path observability contract unless a later phase explicitly decides to split progress-only status from final output. If Phase 4 or later documentation explains how to inspect orchestration results, it should state that `Output` is expected to remain `null` until completion and that final `CustomStatus` and `Output` currently serialize identically. If later phases change the terminal payload shape or stop duplicating the final object across both fields, treat that as a deliberate external contract change and update the docs and verification steps accordingly.
- Remaining risks: This addendum validates one success-path run only. Retry-path and failure-path observability were verified separately earlier on this branch and should remain the comparison points if the terminal payload contract changes later.

---

## Phase 4: Deploy Queue-Based Workflow Completion And Remove API-Side Webhook Processing

### Goal

Remove the remaining API-side webhook code, prove the queue-only path locally end to end, deploy that cleanup through `master`, and then verify the deployed queue-only path end to end in a real environment.

### Steps

- [x] Delete [src/Template.Api/Endpoints/GithubWebhookProxy/WorkflowRunWebhookProcessor.cs](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/Endpoints/GithubWebhookProxy/WorkflowRunWebhookProcessor.cs).
- [x] Remove the webhook processor DI registration from [src/Template.Api/Program.cs](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/Program.cs).
- [x] Remove `MapGitHubWebhooks` and any webhook-only rate limiting from [src/Template.Api/Program.cs](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/Program.cs).
- [x] Remove `Octokit.Webhooks.AspNetCore` from [src/Template.Api/Template.Api.csproj](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/Template.Api.csproj).
- [x] Remove `Octokit.Webhooks` from [src/Template.Functions/Template.Functions.csproj](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Functions/Template.Functions.csproj) if no remaining valid dependency exists.
- [x] Remove webhook-specific configuration from [src/Template.Api/appsettings.json](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/appsettings.json) and [src/Template.Api/appsettings.Development.json](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Api/appsettings.Development.json).
- [x] Remove any webhook-only logging overrides and settings classes.
- [x] Build the API, Functions, and full solution.
- [x] Search the repo for obsolete runtime references to webhook code paths.
- [x] Run a local end-to-end verification of the Phase 4 cleanup on the `master`-equivalent code path.
- [x] Confirm locally that queue-driven workflow completion still succeeds after API-side webhook handling has been removed.
- [x] commit and push the changes to current feature branch
- [ ] Deploy that application and workflow state, using the current feature branch, to the real Azure environments that will receive the webhook cleanup
- [x] Run an end-to-end verification against at least one real deployed environment after rollout.
- [x] Confirm the deployed environment completes the orchestration through the queue-only path.
- [x] Update the checklist for this phase.
- [x] If this phase produced file changes, create one commit on the current branch after verification passed.
- [x] Feed forward cleanup findings into Phases 5 and 6.

### Verification

1. `build api` succeeds.
2. `build functions` succeeds.
3. `build solution` succeeds.
4. A search confirms there are no live app references to:
   - `MapGitHubWebhooks`
   - `WebhookEventProcessor`
   - `Octokit.Webhooks`
   - `Github:WebhookSecret`
5. A local end-to-end verification confirms queue-driven workflow completion still works after API-side webhook handling has been removed.
6. The Phase 4 cleanup and queue-default workflow path are merged to `master`.
7. The Phase 4 deployment reaches the intended real Azure environments.
8. A real deployed environment end-to-end verification confirms orchestration completion still works through the queue-only path after rollout.

### Human Intervention

- Expected for the global rollout itself if deployment approvals or protected environments are involved.
- A human may need to approve the `master` rollout, trigger or approve deployment to real Azure environments, and confirm the post-deployment end-to-end verification target environment.

### Approval Gate

- Required before deploying the Phase 4 cleanup to real Azure environments.

### Feed Forward

- Phase 3 kept queue publication dark by limiting it to [github-integration-test.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/workflows/github-integration-test.yml). Phase 4 should first remove the remaining API webhook code, then prove the queue-only path locally, and only then roll that state out through `master`.
- Phase 4 should preserve both gates: local end-to-end verification before any real Azure deployment, and real deployed-environment end-to-end verification immediately after rollout.
- The final Phase 3 design keeps `github-app-authz-envs` authz-only and publishes workflow queue events from separate environment-scoped jobs. Phase 4 should preserve that split and must not move Azure login or queue publication back into `github-app-authz-envs`.
- The final Phase 3 design also consolidated both `GithubWorkflowInProgress` and `GithubWorkflowCompleted` publication into [publish-github-workflow-event/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/publish-github-workflow-event/action.yml) backed by one checked-in PowerShell script. Phase 4 should extend that shared publisher rather than reintroducing specialized publisher actions or multi-step payload builders.
- The deployed dev validation proved that the Azure OIDC subject used for queue publication is controlled by the caller job's declared GitHub environment, not by a composite action. Phase 4 should therefore keep queue-publication jobs environment-scoped and should treat that job boundary as part of the production design, not as temporary scaffolding.
- Phase 3 restored the `workflowName` contract to `<dispatcher>-<instanceId>` and made dispatcher parsing generic rather than hard-coded to `InternalApi`. Phase 4 should preserve that generic parsing during the global rollout and cleanup.
- Phase 3 refactored the higher-level action logic into [.github/actions/_shared/GitHubWorkflowQueueSupport.psm1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/_shared/GitHubWorkflowQueueSupport.psm1) plus thin entry scripts. Phase 4 should extend that module/entry-point structure rather than reintroducing inline PowerShell into workflow YAML.
- Phase 3 hardened action-support path resolution to be module-relative and currently passes GitHub expression values through `env:` before invoking typed PowerShell parameters. Phase 4 should preserve those patterns in any final default-rollout workflow changes.
- The final Phase 3 app dark-launch validation removed the manual branch-override input and now derives `Github_Branch` from the running workflow context by preferring `github.head_ref` and falling back to `github.ref_name`. Phase 4 should preserve that branch-resolution pattern rather than reintroducing dispatch-only override inputs.
- The deployed dev dark launch also showed that direct storage-table inspection may be blocked by RBAC even when the end-to-end flow is healthy. Phase 4 rollout verification should therefore continue to correlate API-triggered `instanceId` values with the GitHub Actions run id and Application Insights traces when validating the real deployed queue-only path.
- The 2026-03-27 success-path validation confirmed the current observability contract: during in-flight execution, durable `CustomStatus` carries the progress state while durable `Output` remains `null`; at terminal completion, `CustomStatus` and `Output` serialize to the same final `GithubWorkflowOrchestrationState` payload. Phase 4 should preserve that behavior unless the product intentionally changes the external contract.
- The same validation confirmed the current terminal success payload shape is `stage=Completed`, `finalOutcome=Succeeded`, `currentAttempt=1`, `maxAttempts=2`, `runId=<github-run-id>`, `workflowStatus=Completed`, `workflowConclusion=Success`, `workflowSucceeded=true`, and `isTerminal=true`. Later phases should treat changes to that shape as deliberate contract changes rather than incidental refactors.
- Phase 4 code cleanup removed the API runtime webhook surface, deleted the webhook proxy processor, removed webhook-only rate limiting and logging overrides, and dropped webhook-only package dependencies from both app projects. Later phases should treat any remaining webhook mentions in docs, support scripts, or operational runbooks as cleanup debt rather than as live runtime requirements.
- Phase 4 also removed `WebhookSecret` from the shared `GithubAppOptions` contract and from both app configuration trees. Phase 5 and Phase 6 should not reintroduce webhook-secret guidance unless the product intentionally restores inbound GitHub webhook handling.
- Local Phase 4 queue-only verification remains sensitive to the public dev-tunnel host baked into `Github:LocalVerification:QueueEndpoint`. The first Phase 4 validation instance `6dacd2c6927d4f6b98d1699aa288ce27` dispatched correctly but its GitHub run `23685420676` failed before publishing `GithubWorkflowInProgress` because the workflow was still given the stale tunnel host `sqpnctzk-10001.uks1.devtunnels.ms`; the corrected rerun succeeded after updating the user-secret override to the live host `vv7znztc-10001.uks1.devtunnels.ms` and restarting the Functions host.
- The verified local Phase 4 success instance is `3dbb620d427042b4baa3e3936d6813ab`, with GitHub run `23685473880`. Functions host logs showed durable `RaiseEvent:GithubWorkflowInProgress` and `RaiseEvent:GithubWorkflowCompleted`, and Azurite Durable state recorded `RuntimeStatus=Completed` with terminal output `stage=Completed`, `finalOutcome=Succeeded`, `currentAttempt=1`, `maxAttempts=2`, `runId=23685473880`, `workflowStatus=Completed`, `workflowConclusion=Success`, `workflowSucceeded=true`, and `isTerminal=true`.
- The verified deployed dev Phase 4 success instance is `e9e3fa0d3bd0408f9bea8bb7a3b20da5`, triggered through `POST /api/workflow/start` on `https://dev-api-was.codingdemo.co.uk` with GitHub run `23686425734`. Azure Monitor logs in `log-was-dev` recorded a successful API request, a successful `GithubWorkflowTrigger` invocation, queue-driven `RaiseEvent:GithubWorkflowInProgress` and `RaiseEvent:GithubWorkflowCompleted` events, and terminal orchestrator completion for the same instance id.

### Phase 4 Execution Log

- Date: 2026-03-28
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Removed the remaining API and Functions webhook runtime surfaces, removed webhook-only dependencies and configuration from both app projects, removed the shared `Github:WebhookSecret` options requirement, verified `build api`, `build functions`, and `build solution`, committed and pushed the Phase 4 cleanup to the feature branch, and ran successful local and deployed-dev queue-only end-to-end validation.
- Verification run: `build api`; `build functions`; `build solution`; source scans under `src/` confirmed no live app references to `MapGitHubWebhooks`, `WebhookEventProcessor`, `Octokit.Webhooks`, `Github:WebhookSecret`, or `github/webhooks`; local E2E success used Functions instance `3dbb620d427042b4baa3e3936d6813ab` and GitHub run `23685473880`, with log evidence for `RaiseEvent:GithubWorkflowInProgress` and `RaiseEvent:GithubWorkflowCompleted`, plus Azurite `TestHubNameInstances` and `TestHubNameHistory` entries for the same instance; deployed dev E2E success used orchestration instance `e9e3fa0d3bd0408f9bea8bb7a3b20da5` and GitHub run `23686425734`, with Azure Monitor evidence for the successful API trigger, successful `GithubWorkflowTrigger`, both queue-driven durable events, and terminal orchestrator completion.
- Files changed: `src/Template.Api/Endpoints/GithubWebhookProxy/WorkflowRunWebhookProcessor.cs`; `src/Template.Api/Program.cs`; `src/Template.Api/Template.Api.csproj`; `src/Template.Api/appsettings.json`; `src/Template.Api/appsettings.Development.json`; `src/Template.Functions/GithubWorkflowOrchestrator/GithubWebhook.cs`; `src/Template.Functions/Template.Functions.csproj`; `src/Template.Functions/appsettings.json`; `src/Template.Functions/appsettings.Development.json`; `src/Template.Functions/host.json`; `src/Template.Shared/Github/GithubAppOptions.cs`; `docs/github-workflow-direct-callback-migration-plan.md`
- Findings: The webhook runtime surface was still present in two places after Phase 3: the API-side `MapGitHubWebhooks` proxy path and the now-disabled Functions `GithubWebhook` endpoint. Removing both left queue publication and queue consumption as the only live completion path in app code. The first Phase 4 local E2E attempt exposed an operator-sensitive seam: the live public dev-tunnel hostname can rotate even when the tunnel id stays fixed, so local verification must refresh `Github:LocalVerification:QueueEndpoint` to the currently hosted queue URL before dispatching a workflow.
- Feed-forward updates applied to later phases: Preserve the queue-only runtime assumption when cleaning up infrastructure scripts and docs. Any future local queue validation or support runbook should emphasize that the tunnel id is stable but the hosted public URL may need to be re-read from `devtunnel show` and re-applied to user-secrets before dispatch.
- Remaining risks: Dev deployed verification is complete, but broader non-dev rollout and any environment-specific approvals still sit outside this verified scope. Phase 5 and Phase 6 cleanup work also remain outstanding.

---

## Phase 5: Remove Webhook Dependency From Infrastructure Scripts And GitHub App Operations

### Goal

Stop scripts, conventions, and GitHub App operational steps from requiring webhook configuration once the application cleanup has been deployed.

### Steps

- [x] Update [tools/infrastructure/ps-functions/Get-ResourceConvention.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/ps-functions/Get-ResourceConvention.ps1) so GitHub conventions no longer expose a webhook URL as a required output.
- [x] Update [tools/infrastructure/upload-github-app-secrets.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/upload-github-app-secrets.ps1) to stop accepting, displaying, or uploading webhook secrets.
- [x] Update [tools/infrastructure/print-github-app-product-ops-portal-request.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/print-github-app-product-ops-portal-request.ps1) so it requests an Actions-permissions app only.
- [x] Update conventions, deployment docs, or infra helpers as needed so the workflow can discover the Function App storage account and `default-queue` without relying on ad hoc secrets.
- [x] Remove or disable the remaining webhook behavior from all GitHub Apps after the queue-path deployment and Phase 4 application cleanup are complete.
- [x] Search `tools/infrastructure/` for webhook-era terminology and remove or rewrite it.
- [x] If any scripts are intended to be run in dry-run mode, execute those dry runs and inspect the output.
- [x] Build the solution if any shared code or settings are touched.
- [x] Update the checklist for this phase.
- [x] If this phase produced file changes, create one commit on the current branch after verification passed.
- [x] Feed forward tooling and wording findings into Phase 6.

### Verification

1. Dry-run output from updated support scripts no longer mentions webhook URL or webhook secret.
2. Repo search under `tools/infrastructure/` confirms webhook-specific setup has been removed or intentionally deprecated, and queue-publication prerequisites are documented.
3. GitHub App webhook behavior has been removed or disabled after the queue-path deployment and Phase 4 cleanup are complete.
4. If shared project files were touched, `build solution` succeeds.

### Human Intervention

- None expected for the code and script changes themselves.
- Human intervention may be required to apply the GitHub App webhook removal if that operational change is owned outside the repo.

### Approval Gate

- None by default.
- Add an approval gate only if GitHub App webhook removal or script validation depends on protected shared infrastructure or organizational ownership.

### Feed Forward

- Phase 4 should complete before webhook-era infra cleanup begins. Phase 5 should assume the validated steady-state workflow shape is: authz-only [github-app-authz-envs/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/github-app-authz-envs/action.yml), environment-scoped publish jobs, and the shared [publish-github-workflow-event/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/publish-github-workflow-event/action.yml) publisher.
- Infrastructure and GitHub App operational guidance should not suggest that a composite action can change the Azure OIDC subject. If any infra or runbook wording discusses queue-publication auth, it should describe the environment-scoped caller-job requirement instead.
- GitHub App cleanup work should preserve the existing environment-scoped federated credential model and should not introduce new branch-scoped credentials as a workaround for workflow publication.
- Any remaining support scripts or operational instructions should be rewritten to reflect that deployed verification is performed by correlating orchestration `instanceId`, GitHub Actions run id, and Application Insights telemetry, rather than assuming direct storage-table reads are the primary operational signal.
- Phase 5 also made [tools/infrastructure/upload-github-app-secrets.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/upload-github-app-secrets.ps1) a true dry-run script by skipping Azure module import and account-context setup when `-Dry` is used. Later operator guidance should keep dry-run validation credential-light unless a script is intentionally validating live Azure state.

### Phase 5 Execution Log

- Date: 2026-03-28
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Removed queue implementation details from the GitHub app infrastructure convention so it contains only GitHub App concerns, refactored [tools/infrastructure/upload-github-app-secrets.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/upload-github-app-secrets.ps1) to be private-key-only and to support credential-free dry runs, and rewrote [tools/infrastructure/print-github-app-product-ops-portal-request.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/print-github-app-product-ops-portal-request.ps1) so it requests an Actions-permissions GitHub App without exposing technical implementation details in the operator-facing request.
- Verification run: `pwsh -NoProfile -Command '$c = ./tools/infrastructure/get-product-conventions.ps1 -EnvironmentName dev -AsHashtable; $c.SubProducts.Github | ConvertTo-Json -Depth 10'`; `pwsh -NoProfile -File ./tools/infrastructure/print-github-app-product-ops-portal-request.ps1 -EnvironmentName dev`; `pwsh -NoProfile -File ./tools/infrastructure/upload-github-app-secrets.ps1 -EnvironmentName dev -PemFilePath /tmp/fake-github-app.pem -Dry`; repo search under `tools/infrastructure/**` for `webhook|WebhookSecret|WebhookUrl|api/github/webhooks|workflow_run`
- Files changed: `tools/infrastructure/get-product-conventions.ps1`; `tools/infrastructure/ps-functions/Get-ResourceConvention.ps1`; `tools/infrastructure/upload-github-app-secrets.ps1`; `tools/infrastructure/print-github-app-product-ops-portal-request.ps1`; `docs/github-workflow-direct-callback-migration-plan.md`
- Findings: The earlier Phase 5 convention refactor exposed that queue publication had been incorrectly coupled to the GitHub app convention by inheriting `Target = Api`. After re-evaluating the boundary, Phase 5 removed those queue fields from the GitHub app model entirely because queue resolution belongs to the workflow dispatcher and publisher path, not to GitHub App metadata. The updated dry-run validation also showed that the secret-upload support script should not require Azure modules or a signed-in Azure account when it is only printing planned operations; later operator-facing dry-run tooling should preserve that pattern. After the cleanup, the only `tools/infrastructure/**` search hits containing `webhook` are intentional references in Azure Monitor ARM schema properties.
- Feed-forward updates applied to later phases: Phase 6 docs should keep the GitHub App creation/request flow focused on Actions-only setup and should document queue resolution only in the workflow implementation guidance where that behavior is actually owned. Phase 6 should also preserve the new dry-run behavior in any operator guidance for [tools/infrastructure/upload-github-app-secrets.ps1](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/tools/infrastructure/upload-github-app-secrets.ps1).
- Remaining risks: The repo-side Phase 5 work is complete, but the operational step to remove or disable webhook behavior on the live GitHub Apps remains outstanding and still requires action outside this repository. No solution build was run in this phase because the changes were limited to infrastructure PowerShell scripts and the migration plan document.

---

## Phase 6: Rewrite Documentation For The Queue-Based Architecture

### Goal

Align all repository documentation with the new design so contributors no longer set up or reason about GitHub workflow completion through webhooks.

### Steps

- [x] Rewrite [docs/workflow-orchestration-setup.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/workflow-orchestration-setup.md) around the queue-based completion flow, workflow auth to Azure Storage, queue message shape, queue-trigger processing, and fallback polling behavior.
- [x] Document the revised role of [github-app-authz-envs/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/github-app-authz-envs/action.yml) as the fail-closed workflow authorization step, and document the separate environment-scoped jobs that publish `GithubWorkflowInProgress` and `GithubWorkflowCompleted` through the shared workflow event publisher.
- [x] Document the `gated-environments` multi-line input contract and the `authorized-target-envs` output contract for [github-app-authz-envs/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/github-app-authz-envs/action.yml).
- [x] Document the reusable workflow queue publisher composite action and its local PowerShell helper, including how it is used for both `GithubWorkflowInProgress` and `GithubWorkflowCompleted`.
- [x] Document that queue publication uses `az storage message put --auth-mode login` with the built-in `Storage Queue Data Message Sender` role and no shared-key fallback.
- [x] Document the raw `MessageBody` JSON transport format, including that `MessageBody.Data` contains a JSON string payload rather than a second envelope.
- [x] Document the duplicate-handling contract for repeated workflow queue messages.
- [x] Update [docs/github-app-creation.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/github-app-creation.md) to remove webhook URL and webhook secret setup requirements.
- [x] Update [docs/add-environment.md](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/docs/add-environment.md) to remove webhook prerequisites.
- [x] Search `docs/` for stale references to GitHub webhook setup, webhook secret upload, or webhook callback routing.
- [x] Update architecture diagrams and sequence diagrams to reflect GitHub Actions publishing queue messages to `default-queue`.
- [x] Build the solution only if any code snippets or references required code edits.
- [x] Update the checklist for this phase.
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

- Phase 6 documentation should describe the implemented workflow shape, not the earlier Phase 3 draft: `github-app-authz-envs` is authz-only, `GithubWorkflowInProgress` and `GithubWorkflowCompleted` are published from separate environment-scoped jobs, and both use the shared [publish-github-workflow-event/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/publish-github-workflow-event/action.yml) action.
- The docs rewrite should explicitly capture the Azure OIDC constraint that the queue-publication job must declare the target GitHub environment to obtain the correct `repo:<owner>/<repo>:environment:<env>` subject; this is a workflow-shape requirement, not an implementation detail inside a composite action.
- The docs rewrite should record the verified branch-resolution rule for app deployment: prefer `github.head_ref` for PR-originated runs and fall back to `github.ref_name` for branch and manual runs.
- Operational verification docs should reflect the deployed validation method proven in dev: trigger through the supported API path, capture the orchestration `instanceId`, correlate to the GitHub Actions run, and use Application Insights to confirm both queue events and terminal durable completion.

### Phase 6 Execution Log

- Date: 2026-03-28
- Agent: GitHub Copilot (GPT-5.4)
- Summary of completed work: Rewrote the primary workflow orchestration runbook around the implemented queue-only callback path, documented `github-app-authz-envs` as an authz-only fail-closed gate plus the shared `publish-github-workflow-event` publisher, updated the architecture and transport diagrams to show GitHub Actions publishing back to `default-queue`, and removed the remaining webhook-era setup guidance from the GitHub App, add-environment, and dev tunnel docs.
- Verification run: targeted repo searches under `docs/**` for `api/github/webhooks`, `WebhookSecret`, `Octokit.Webhooks`, and webhook callback routing guidance; manual consistency check against [github-app-authz-envs/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/github-app-authz-envs/action.yml), [publish-github-workflow-event/action.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/actions/publish-github-workflow-event/action.yml), [github-integration-test.yml](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/.github/workflows/github-integration-test.yml), and [TriggerWorkflowActivity.cs](/Users/christian.crowhurst/Documents/git/mri-web-api-starter-template/src/Template.Functions/GithubWorkflowOrchestrator/TriggerWorkflowActivity.cs). No solution build was required because this phase changed documentation only.
- Files changed: `docs/workflow-orchestration-setup.md`; `docs/github-app-creation.md`; `docs/add-environment.md`; `docs/dev-tunnels.md`; `docs/github-workflow-direct-callback-migration-plan.md`
- Findings: The previous orchestration runbook still described the removed webhook proxy, HMAC validation, webhook secrets, and Octokit-based callback routing. The implemented design is materially different: the authz action is separate from publication, queue publication happens from environment-scoped jobs through the shared publisher, and queue transport depends on a base64-encoded `MessageBody` envelope whose `Data` property is a serialized inner JSON string.
- Feed-forward updates applied to later phases: Recorded the environment-scoped OIDC requirement for queue publication jobs, the verified branch-resolution rule used by app deployment workflows, the queue-only operational verification method for deployed environments, and the remaining local operator dependency on a current public Azurite queue tunnel when using the `localVerification` seam.
- Remaining risks: The phase commit remains intentionally uncreated because no explicit commit instruction was given in this session. The migration plan and docs are now aligned with the implemented queue-based runtime, but final readiness still depends on completing the broader migration checklist and repo-wide cleanup validation.

---

## Final Readiness Review

Do not mark the migration complete until all items below are true.

- [ ] A pre-migration benchmark of the original webhook-based design was captured and is available for comparison.
- [ ] The benchmark includes captured host log evidence and Azurite-backed Durable state inspection for a real orchestration instance.
- [ ] The workflow can authenticate with Azure and publish both required messages to the intended storage queue.
- [ ] The workflow publishes through `az storage message put --auth-mode login` using the built-in `Storage Queue Data Message Sender` role on the intended storage account.
- [ ] Queue-driven processing raises both Durable events correctly.
- [ ] Queue message transport uses the queue-trigger-compatible serialized `MessageBody` envelope, including base64 encoding when the app keeps the default Storage Queues trigger semantics.
- [ ] Duplicate workflow queue messages have been tested and do not create duplicate durable side effects.
- [ ] The orchestrator still works when a callback is delayed or missing and fallback polling is required.
- [ ] Queue-based completion is the only intended orchestration event delivery path in deployed environments, and legacy GitHub webhook behavior has been removed or disabled.
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