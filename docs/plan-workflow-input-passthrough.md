# Plan: Workflow-Specific Input Pass-Through

## TL;DR

Add an optional `WorkflowInputs` dictionary that flows from the HTTP trigger through
`OrchestratorInput` → `TriggerInput` → `TriggerWorkflowActivity`, where it is merged
with (and protected by) the two reserved orchestration keys `workflowName` and
`localVerification`. Separately, harden the orchestrator so that an activity failure
during workflow dispatch (e.g., a GitHub HTTP 422 from an undeclared input key) produces
a clean, shaped terminal `Failed` state rather than an unhandled Durable crash.

---

## Key design decisions

- **Reserved keys** are `"workflowName"` and `"localVerification"` — already hardcoded
  string literals in `TriggerWorkflowActivity`. No casing ambiguity: all consumer-supplied
  keys are validated with `StringComparer.Ordinal` against those exact literals.
- **Validation lives in the activity**, not the orchestrator or the trigger, because the
  reserved keys are an implementation detail of `TriggerWorkflowActivity`. The
  orchestrator catches any resulting `TaskFailedException` and shapes it.
- **Merge order**: caller inputs first, then reserved keys overwrite. This guarantees
  the orchestration correlation key (`workflowName`) can never be hijacked by a caller.
- **Reruns are NOT changed**: GitHub reruns inherit the original run's inputs automatically.
  `RerunFailedJobActivity` and `RerunEntireWorkflowActivity` are untouched.
- **`GithubWorkflowOrchestrationStage.InvalidInput`** is the correct stage to use when the
  orchestrator catches a dispatch-time `TaskFailedException`, because from the orchestrator's
  perspective the dispatch could not be initiated.

---

## Phase 0 — Research: GitHub API error fidelity through Octokit and Durable

**Status**: Complete. Findings are incorporated into the design decisions and Phase 3 steps below.

### Research questions answered

**Q1: Does GitHub return `application/problem+json` for invalid `workflow_dispatch` inputs?**

No. GitHub uses its own JSON error envelope:
```json
{
  "message": "top-level error description",
  "errors": [
    { "message": "...", "code": "...", "field": "...", "resource": "..." }
  ],
  "documentation_url": "https://docs.github.com/..."
}
```
GitHub returns HTTP 422 when any key in `inputs` was not declared in the workflow's `on.workflow_dispatch.inputs`.

**Q2: Does Octokit.NET surface structured error detail, or just a raw string?**

Octokit fully deserializes the GitHub error envelope into `ApiValidationException` (which extends `ApiException`):
- `ex.ApiError.Message` — top-level error string (e.g. `"Workflow does not have 'foo' input"`)
- `ex.ApiError.Errors` — `IReadOnlyList<ApiErrorDetail>`, each with `Message`, `Code`, `Field`, `Resource`
- `ex.ApiError.DocumentationUrl` — link to GitHub docs
- `ex.ToString()` — appends the full raw HTTP response body

So: **yes**, Octokit gives us rich, structured error information at the activity call site.

**Q3: What survives the Durable serialization boundary into the orchestrator?**

When an activity throws, the Durable isolated worker serializes the exception into `TaskFailureDetails`:
- `FailureDetails.ErrorMessage` ← `Exception.Message` only (the top-level string)
- `FailureDetails.ErrorType` ← full type name (e.g. `"Octokit.ApiValidationException"`)
- `FailureDetails.StackTrace` ← stack trace string
- `FailureDetails.InnerFailure` ← nested failure details

The structured `ApiError.Errors` collection is **silently dropped** at this boundary — it never reaches the orchestrator's catch block.

Application Insights telemetry **does** capture the full original `ApiValidationException` from the activity (including `ToString()` and raw body), so observability is good on the AI side. But the shaped state's `Message` field, if populated from `FailureDetails.ErrorMessage`, would only contain the single top-level message string.

**Q4: What do we need to do to preserve full detail through Durable?**

Catch `ApiValidationException` inside the activity and rethrow as `InvalidOperationException` with a message that includes all field-level detail:
```csharp
catch (ApiValidationException ex)
{
    var details = ex.ApiError?.Errors is { Count: > 0 }
        ? "; details: " + string.Join(", ", ex.ApiError.Errors.Select(e => e.Message ?? e.Code))
        : string.Empty;
    throw new InvalidOperationException(
        $"GitHub rejected the workflow dispatch (HTTP 422): {ex.Message}{details}", ex);
}
```
This ensures the enriched string — including all `ApiErrorDetail.Message` values — is what Durable copies into `FailureDetails.ErrorMessage`, and therefore into the shaped state and the operator-visible log.

**Q5: Is `IExceptionPropertiesProvider` a better mechanism than catch-and-rethrow for preserving structured error data?**

`IExceptionPropertiesProvider` (`Microsoft.DurableTask.Worker.IExceptionPropertiesProvider`) is the
correct Durable-native mechanism for preserving structured exception properties across the activity
boundary. The interface method `GetExceptionProperties(Exception) → IDictionary<string, object?>?`
is called by the Durable runtime when serializing any activity exception, and the returned dictionary
lands in `TaskFailureDetails.Properties` — readable by the orchestrator as structured data.

However, using it here has two blockers:

1. **Package version**: The feature was added in durabletask-dotnet PR #474 (merged Oct 13, 2025).
   This project uses `Microsoft.Azure.Functions.Worker.Extensions.DurableTask` **1.13.1**, which
   predates the feature. Upgrading to ≥ 1.19.1 would be required — a separate, non-trivial change.

2. **Scope mismatch**: `IExceptionPropertiesProvider` is registered globally at the DI/worker level
   and intercepts ALL exceptions from ALL activities. It adds `Properties` to `TaskFailureDetails`
   for programmatic access by the orchestrator. The goal here is a readable diagnostic message in
   the Durable Monitor and shaped state — which is `FailureDetails.ErrorMessage`, not `Properties`.
   These are different fields; `IExceptionPropertiesProvider` does not help with `ErrorMessage`.

Catch-and-rethrow solves the `ErrorMessage` richness problem with zero dependency changes. If a
future requirement needs the orchestrator to make **programmatic retry decisions** based on GitHub
error codes (e.g. back off on 429 vs. fail fast on 422), adding `IExceptionPropertiesProvider`
at that point would be the right extension.

### Design decisions updated from research

- **Phase 3** gains an additional step: catch `ApiValidationException` after `CreateDispatch` and rethrow as `InvalidOperationException` with a message that concatenates all `ApiErrorDetail.Message` values. `ApiValidationException` is caught specifically (not `ApiException`) because other HTTP errors (e.g. 401) should propagate differently.
- **Phase 4** no longer needs `ex.InnerException?.Message` logic — `FailureDetails.ErrorMessage` is now the fully enriched string built in the activity.
- **`IExceptionPropertiesProvider` is explicitly deferred**: not used here due to package version constraint and scope mismatch. Revisit if orchestrator-level programmatic error inspection is ever needed.

---

## Cross-cutting agent instructions

> After completing each implementation phase:
>
> 1. **Tick completed steps** — change `- [ ]` → `- [x]` immediately after each step is done. Do not batch ticks.
> 2. **Code review** — work through the code-review checklist at the end of the phase before moving to the next phase.
> 3. **Refactor** — fix every smell found. Record what was changed.
> 4. **Feed forward** — update the remaining phase steps if discoveries in the current phase affect the approach.

---

## Phase 1 — Data model changes

**Files**: `StartWorkflowRequest.cs`, `OrchestratorInput.cs`, `TriggerInput.cs`

### Steps

- [x] Read `StartWorkflowRequest.cs`, `OrchestratorInput.cs`, and `TriggerInput.cs` to confirm current content before editing.
- [x] Add to `StartWorkflowRequest`:
  ```csharp
  public Dictionary<string, string>? WorkflowInputs { get; set; }
  ```
- [x] Add to `OrchestratorInput`:
  ```csharp
  public Dictionary<string, string>? WorkflowInputs { get; set; }
  ```
- [x] Add to `TriggerInput`:
  ```csharp
  public Dictionary<string, string>? WorkflowInputs { get; set; }
  ```
- [x] Run `dotnet build src/Template.Functions/Template.Functions.csproj` and confirm zero errors.

### Code review

- [x] Are the type choices (`Dictionary<string, string>?`) consistent with how the inputs will be used downstream (merged into `Dictionary<string, object>` in the activity)?
- [x] `Dictionary<string, string>?` is used across all three models for serialization compatibility: `System.Text.Json` (HTTP request body and Durable Functions checkpointing) cannot deserialize into `IReadOnlyDictionary` directly.
- [x] No validation attribute (`[Required]`, `[MinLength]`) needed — `WorkflowInputs` is intentionally optional in all three models.
- [x] No other properties in these files are affected by the additions.

### Feed forward

- [x] All three models use `Dictionary<string, string>?`. Phase 2 assignment is a direct reference pass — no conversion needed.

---

## Phase 2 — Propagation

**Files**: `GithubWorkflowTrigger.cs`, `GithubWorkflowOrchestrator.cs`

### Steps

- [x] Read `GithubWorkflowTrigger.cs` to confirm the current `OrchestratorInput` initializer.
- [x] In `GithubWorkflowTrigger.RunAsync`, add `WorkflowInputs = workflowRequest.WorkflowInputs` to the `OrchestratorInput` initializer.
- [x] Read `GithubWorkflowOrchestrator.cs` `TriggerWorkflowAsync` to confirm the current `TriggerInput` initializer.
- [x] In `GithubWorkflowOrchestrator.TriggerWorkflowAsync`, add `WorkflowInputs = input.WorkflowInputs` to the `TriggerInput` initializer.
- [x] Run `dotnet build src/Template.Functions/Template.Functions.csproj` and confirm zero errors.

### Code review

- [x] Is `input.WorkflowInputs` simply passed by reference into `TriggerInput`? The activity only reads from it (via a `foreach` with a null guard); no mutation occurs at either end, so sharing the same `Dictionary<string, string>?` reference is safe.
- [x] No other changes to `GithubWorkflowTrigger.RunAsync` or `TriggerWorkflowAsync` are needed — confirm stray edits are absent.

### Feed forward

- [x] No known issues. Proceed to Phase 3.

---

## Phase 3 — Activity merge and input validation

**File**: `TriggerWorkflowActivity.cs`

### Steps

- [x] Read `TriggerWorkflowActivity.RunAsync` to confirm the current `workflowInputs` dictionary construction.
- [x] At the very top of `RunAsync` (before `GetOrCreateClientAsync()`), add reserved-key validation:
  ```csharp
  private static readonly HashSet<string> ReservedInputKeys =
      new(StringComparer.Ordinal) { "workflowName", "localVerification" };

  // In RunAsync, before the workflowInputs dictionary is created:
  if (input.WorkflowInputs != null)
  {
      var collision = input.WorkflowInputs.Keys
          .FirstOrDefault(k => ReservedInputKeys.Contains(k));
      if (collision != null)
      {
          throw new InvalidOperationException(
              $"WorkflowInputs contains the reserved orchestration key '{collision}'. " +
              "This key is managed by the dispatcher and must not be supplied by the caller.");
      }
  }
  ```
- [x] Merge caller inputs before the reserved keys are written, so reserved keys always win:
  ```csharp
  var workflowInputs = new Dictionary<string, object>();

  if (input.WorkflowInputs != null)
  {
      foreach (var (key, value) in input.WorkflowInputs)
          workflowInputs[key] = value;
  }

  workflowInputs["workflowName"] = workflowName;

  var localVerificationDirective = BuildLocalVerificationDirective();
  if (!string.IsNullOrWhiteSpace(localVerificationDirective))
      workflowInputs["localVerification"] = localVerificationDirective;
  ```
- [x] Confirm the existing `workflowName` and `localVerification` assignment lines are removed / replaced (not duplicated).
- [x] After the `CreateDispatch` call, add `ApiValidationException` catch-and-rethrow to preserve field-level error detail through the Durable serialization boundary:
  ```csharp
  // Wrap the CreateDispatch call:
  try
  {
      await githubClient.Actions.Workflows.CreateDispatch(options.Owner, options.Repo,
          input.WorkflowFile, workflowDispatchRequest);
  }
  catch (ApiValidationException ex)
  {
      var details = ex.ApiError?.Errors is { Count: > 0 }
          ? "; details: " + string.Join(", ", ex.ApiError.Errors.Select(e => e.Message ?? e.Code))
          : string.Empty;
      throw new InvalidOperationException(
          $"GitHub rejected the workflow dispatch (HTTP {(int)ex.StatusCode}): {ex.Message}{details}", ex);
  }
  ```
  > **Why**: Durable only serializes `Exception.Message` across the activity boundary. `ApiValidationException.ApiError.Errors` (the structured per-field detail) is silently dropped. Wrapping into `InvalidOperationException` with a message that includes all `ApiErrorDetail.Message` values ensures the full detail survives into `FailureDetails.ErrorMessage`, the shaped state's `Message` field, and operator-visible logs. See Phase 0 for the full research.
- [x] Run `dotnet build src/Template.Functions/Template.Functions.csproj` and confirm zero errors.

### Code review

- [x] Is `ReservedInputKeys` declared at the right scope? It is a static, immutable set — placing it as a `private static readonly` field on the class is correct.
- [x] Does the merge loop correctly handle a `null` `WorkflowInputs`? (Guard is `if (input.WorkflowInputs != null)`.)
- [x] Is the `InvalidOperationException` message precise enough for an operator diagnosing a reserved-key collision?
- [x] Does the reserved-key validation run before `GetOrCreateClientAsync()` (moved to the top of `RunAsync` per the step above)?
- [x] Does the merge preserve all caller-supplied values, including values that are empty strings (valid for optional workflow inputs)?
- [x] Does the `ApiValidationException` catch wrap only `CreateDispatch`, and not broader code (so that unexpected API errors in other calls are not silently swallowed)?
- [x] Does the catch include the original `ApiValidationException` as `innerException` so App Insights retains the full stack and raw HTTP body alongside the shaped message?

### Feed forward

- [x] Validation runs before `GetOrCreateClientAsync()` — exception is thrown at the top of the activity before any I/O. Phase 4 `TaskFailedException` wraps this `InvalidOperationException`.

---

## Phase 4 — Clean terminal state on activity failure

**File**: `GithubWorkflowOrchestrator.cs`

**Context**: When `TriggerWorkflowActivity` throws (either `InvalidOperationException` from a
reserved-key collision or `ApiValidationException` from a GitHub HTTP 422), the Durable runtime
surfaces this to the orchestrator as a `TaskFailedException`. Without a catch, the orchestration
crashes raw — no `GithubWorkflowOrchestrationState` is ever written, and the consumer sees an
unstructured Durable `Failed` state instead of a shaped outcome.

### Steps

- [x] Read `GithubWorkflowOrchestrator.RunAsync` to confirm the current call site of `TriggerWorkflowAsync`.
- [x] Wrap the `TriggerWorkflowAsync` call in `RunAsync` with a try/catch:
  ```csharp
  try
  {
      var (_, runId) = await TriggerWorkflowAsync(context, input, initialAttempt);
      // ... existing WaitForWorkflowAttemptResultAsync and RetryWorkflowUntilTerminalAsync calls ...
  }
  catch (TaskFailedException ex)
  {
      var logger = context.CreateReplaySafeLogger<GithubWorkflowOrchestrator>();
      logger.LogError(ex, "Workflow dispatch failed; terminating orchestration as Failed.");

      return Complete(
          context,
          CreateState(
              stage: GithubWorkflowOrchestrationStage.InvalidInput,
              currentAttempt: initialAttempt,
              maxAttempts: input.MaxAttempts,
              finalOutcome: GithubWorkflowOrchestrationFinalOutcome.Failed,
              isTerminal: true,
              message: $"Workflow dispatch failed and the orchestration cannot proceed: {ex.FailureDetails.ErrorMessage}"));
  }
  ```
  > **Note on `FailureDetails.ErrorMessage`**: because Phase 3 catches `ApiValidationException` in the activity and rethrows as `InvalidOperationException` with a message that includes all `ApiErrorDetail.Message` values, `FailureDetails.ErrorMessage` already contains the fully enriched string. No `InnerException?.Message` fallback is needed.
  ```
- [x] Confirm try block wraps only `TriggerWorkflowAsync` (narrow scope per code review guidance); `WaitForWorkflowAttemptResultAsync` and `RetryWorkflowUntilTerminalAsync` remain outside to prevent masking post-dispatch failures.
- [x] Run `dotnet build src/Template.Functions/Template.Functions.csproj` and confirm zero errors.

### Code review

- [x] Catch covers only `TriggerWorkflowAsync` (narrow scope); `WaitForWorkflowAttemptResultAsync` and `RetryWorkflowUntilTerminalAsync` are outside the try block.
- [x] `GithubWorkflowOrchestrationStage.InvalidInput` chosen for dispatch-time failures — consistent with the pre-existing invalid-input path and correct because the dispatch could not be initiated.
- [x] `ex.FailureDetails.ErrorMessage` carries the enriched message — confirmed by Test C output: `"GitHub rejected the workflow dispatch (HTTP 422): Unexpected inputs provided: [\"undeclaredForTest\"]"` was in the shaped state.
- [x] Risk of `TaskFailedException` from rerun exceptions is mitigated by the narrow try block scope.

### Feed forward

- [x] `InvalidInput` stage is used for dispatch failures. `TriggerWorkflowAsync` sets `TriggeringWorkflow` at its start, then the catch in `RunAsync` overrides with `InvalidInput` on failure — consistent.
- [x] Log line with the exception detail is sufficient for local dev. App Insights captures the full original `ApiValidationException` from the activity with complete structured data.

---

## Phase 5 — E2E Verification (agent-automated, local)

**Draws on**: ["Exact Local E2E Validation Procedure"](./workflow-orchestration-setup.md) in `workflow-orchestration-setup.md`.

**Assumption**: You (the agent) are running this procedure. The user has already:
- Signed in to the Entra ID tenant via `az login`
- Signed in to devtunnel via `devtunnel user login`

**No new GitHub push is required** for any of these tests. GitHub `github-integration-test.yml` is used as-is (already on `master`). Tests 2 and 3 exploit the fact that `github-integration-test.yml` does not declare a key called `undeclaredForTest` or `workflowName` as a user-supplied value.

---

### Step 1 — Set shared variables

In terminal (PowerShell), from the repository root:

```pwsh
$FunctionsBaseUrl = 'http://localhost:7071'
$WorkflowFile = 'github-integration-test.yml'
$RepoRoot = (Get-Location).Path
$TmpDir = Join-Path $RepoRoot 'tmp'
$FunctionsLog = Join-Path $TmpDir 'local-workflow-functions.log'
$DurableInstancesLog = Join-Path $TmpDir 'local-workflow-durable-instances.json'
$DurableHistoryLog = Join-Path $TmpDir 'local-workflow-durable-history.json'
$env:GH_PAGER = 'cat'
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null
```

Read `src/Template.Functions/local.settings.json` to extract `AzureWebJobsStorage`:

```pwsh
$LocalSettings = Get-Content ./src/Template.Functions/local.settings.json -Raw | ConvertFrom-Json
$StorageConnectionString = $LocalSettings.Values.AzureWebJobsStorage
$env:AZURE_CLI_DISABLE_CONNECTION_VERIFICATION = '1'
```

---

### Step 2 — Start Azurite, dev tunnel, and Functions app

- [x] Run `./tools/azurite/azurite-run.ps1` in a background terminal and leave it running.
- [x] Identify your dev tunnel id (`devtunnel list`) and host it (`devtunnel host <id>`) in a second terminal; confirm `Host connections: ≥ 1`.
- [x] Build and start the Functions app:
  ```pwsh
  dotnet build ./src/Template.Functions/Template.Functions.csproj
  Set-Location ./src/Template.Functions/bin/Debug/net10.0
  func start *>&1 | Tee-Object -FilePath $FunctionsLog
  ```
- [x] Confirm the health check succeeds before continuing:
  ```pwsh
  Invoke-RestMethod -Method Get -Uri "$FunctionsBaseUrl/api/Echo"
  ```

---

### Test A — Regression: normal dispatch with no `WorkflowInputs`

**Purpose**: Confirm existing behaviour is undisturbed.

- [x] Set the branch and tunnel base URL in user-secrets (as per the full procedure in `workflow-orchestration-setup.md` Steps 1–3) so `localVerification` is populated.
- [x] Trigger the workflow:
  ```pwsh
  $TriggerResponse = Invoke-RestMethod -Method Post -Uri "$FunctionsBaseUrl/api/workflow/start" `
      -ContentType 'application/json' `
      -Body (@{ WorkflowFile = $WorkflowFile; RerunEntireWorkflow = $true } | ConvertTo-Json)
  $InstanceId = $TriggerResponse.Id
  $WorkflowName = "InternalApi-$InstanceId"
  Write-Host "InstanceId: $InstanceId  WorkflowName: $WorkflowName"
  ```
- [x] Wait for the GitHub Actions run to appear and complete (Steps 8–9 of the full procedure).
- [x] Confirm Functions log contains `GithubWorkflowInProgress` and `GithubWorkflowCompleted` for the instance.
- [x] Confirm Durable terminal state in Azurite:
  ```pwsh
  $InstancesJson = az storage entity query --table-name TestHubNameInstances `
      --connection-string "$StorageConnectionString" `
      --filter "PartitionKey eq '$InstanceId'" --only-show-errors -o json
  $InstancesJson | ConvertFrom-Json
  ```
  Expect `FinalOutcome` = `Succeeded` and `IsTerminal` = `true`.

**Pass criteria**: orchestration reaches Completed/Succeeded; queue messages arrive; Functions app log is clean.

**RESULT**: PASSED — `FinalOutcome: Succeeded`, `workflowSucceeded: true`, runId: 23807575580, stage: Completed.

---

### Test B — Reserved-key collision (pre-dispatch, no GitHub call)

**Purpose**: Confirm the activity throws and the orchestrator returns a shaped `Failed` state, without ever calling the GitHub API.

- [x] Clear previous Durable state by restarting the Functions app between tests (or use a distinct instance).
- [x] Trigger with a reserved key:
  ```pwsh
  $CollisionResponse = Invoke-RestMethod -Method Post -Uri "$FunctionsBaseUrl/api/workflow/start" `
      -ContentType 'application/json' `
      -Body (@{
          WorkflowFile   = $WorkflowFile
          WorkflowInputs = @{ workflowName = 'hacked' }
      } | ConvertTo-Json)
  $CollisionInstanceId = $CollisionResponse.Id
  Write-Host "CollisionInstanceId: $CollisionInstanceId"
  ```
- [x] Poll until the orchestration reaches a terminal state (wait up to 30 seconds).
- [x] Inspect the Functions log for the `InvalidOperationException` message:
  ```pwsh
  Select-String -Path $FunctionsLog -Pattern $CollisionInstanceId, 'reserved', 'workflowName' |
      Select-Object LineNumber, Line
  ```

**Pass criteria**:
- Durable instance exists for `$CollisionInstanceId`
- Terminal state has `FinalOutcome` = `Failed` and `IsTerminal` = `true`
- Functions log contains the reserved-key error message
- No GitHub Actions run was dispatched for this instance (verify via `gh run list --workflow $WorkflowFile --limit 5`)

**RESULT**: PASSED — `FinalOutcome: Failed`, `isTerminal: true`, `stage: InvalidInput`, message: "WorkflowInputs contains the reserved orchestration key 'workflowName'. This key is managed by the dispatcher and must not be supplied by the caller."

---

### Test C — GitHub HTTP 422 (undeclared input key)

**Purpose**: Confirm that a GitHub 422 (undeclared workflow input) produces a shaped terminal `Failed` state rather than a raw Durable crash.

> `github-integration-test.yml` does not declare an input named `undeclaredForTest`, so GitHub will return HTTP 422 when such a key is supplied.

- [x] Trigger with an undeclared input key:
  ```pwsh
  $UndeclaredResponse = Invoke-RestMethod -Method Post -Uri "$FunctionsBaseUrl/api/workflow/start" `
      -ContentType 'application/json' `
      -Body (@{
          WorkflowFile   = $WorkflowFile
          WorkflowInputs = @{ undeclaredForTest = 'someValue' }
      } | ConvertTo-Json)
  $Undeclared422InstanceId = $UndeclaredResponse.Id
  Write-Host "Undeclared422InstanceId: $Undeclared422InstanceId"
  ```
- [x] Poll until the orchestration reaches terminal state (wait up to 30 seconds).
- [x] Inspect the Functions log for the GitHub 422 error:
  ```pwsh
  Select-String -Path $FunctionsLog -Pattern $Undeclared422InstanceId, '422', 'Unprocessable', 'dispatch failed' |
      Select-Object LineNumber, Line
  ```

**Pass criteria**:
- Durable instance exists for `$Undeclared422InstanceId`
- Terminal state has `FinalOutcome` = `Failed` and `IsTerminal` = `true`
- The state has a `Message` property that includes the error detail from the `TaskFailedException`
- No Durable orchestration crash (no unhandled exception in the Functions host log for this instance)

**RESULT**: PASSED — `FinalOutcome: Failed`, `isTerminal: true`, `stage: InvalidInput`, message: "GitHub rejected the workflow dispatch (HTTP 422): Unexpected inputs provided: [\"undeclaredForTest\"]"

---

### Test D — Valid `WorkflowInputs` accepted and visible in GitHub run

**Purpose**: Confirm that caller-supplied keys physically arrive as inputs in the dispatched GitHub
Actions run. `github-integration-test.yml` now declares `testMode` (type `choice`) and
`notificationEmail` (type `string`), so a dispatch supplying both should succeed and the run log
should reflect the supplied values.

- [x] Trigger with valid declared inputs:
  ```pwsh
  $ValidInputsResponse = Invoke-RestMethod -Method Post -Uri "$FunctionsBaseUrl/api/workflow/start" `
      -ContentType 'application/json' `
      -Body (@{
          WorkflowFile        = $WorkflowFile
          ReRunEntireWorkflow = $true
          WorkflowInputs      = @{
              testMode           = 'full-regression'
              notificationEmail  = 'dev@example.com'
          }
      } | ConvertTo-Json)
  $ValidInputsInstanceId = $ValidInputsResponse.Id
  Write-Host "ValidInputsInstanceId: $ValidInputsInstanceId"
  ```
- [x] Wait for the GitHub Actions run to appear (poll `gh run list --workflow $WorkflowFile --limit 5`) and complete.
- [x] Inspect the run log for `dev-task` to confirm both values appear:
  ```pwsh
  $RunId = gh run list --workflow $WorkflowFile --json databaseId,displayTitle,status `
      --limit 10 | ConvertFrom-Json |
      Where-Object { $_.displayTitle -like "*$ValidInputsInstanceId*" } |
      Select-Object -First 1 -ExpandProperty databaseId
  gh run view $RunId --log | Select-String 'full-regression|dev@example.com'
  ```
- [x] Confirm the orchestration reaches a terminal `Succeeded` state:
  ```pwsh
  $InstancesJson = az storage entity query --table-name TestHubNameInstances `
      --connection-string "$StorageConnectionString" `
      --filter "PartitionKey eq '$ValidInputsInstanceId'" --only-show-errors -o json
  $InstancesJson | ConvertFrom-Json
  ```

**Pass criteria**:
- Orchestration reaches `FinalOutcome = Succeeded`, `IsTerminal = true`
- GitHub run log for `dev-task` contains `"Test mode: full-regression"` and `"Notification email: dev@example.com"`
- Queue callbacks (`GithubWorkflowInProgress` and `GithubWorkflowCompleted`) arrive as normal

**RESULT**: PASSED — `FinalOutcome: Succeeded`, `workflowSucceeded: true`, runId: 23820362338, stage: Completed. GitHub run log for `dev-task` confirmed `Test mode: full-regression` and `Notification email: dev@example.com`.

---

### Phase 5 pass criteria summary

| Test | Pass condition |
|------|---------------|
| A — Regression | Orchestration reaches `Succeeded`; queue callbacks arrive |
| B — Reserved-key collision | Orchestration reaches `Failed`; log contains reserved-key error; no GitHub run dispatched |
| C — GitHub 422 | Orchestration reaches `Failed`; log contains dispatch-failed error; no Durable crash |
| D — Valid inputs passthrough | Orchestration reaches `Succeeded`; GitHub run log shows `testMode=full-regression` and `notificationEmail=dev@example.com` |

---

## Out of scope

- `RerunFailedJobActivity` and `RerunEntireWorkflowActivity` — reruns inherit original run inputs from GitHub automatically.
- `GetRecentWorkflowRunActivity`, `GetWorkflowRunStatusActivity` — no input forwarding relevant.
- `github-integration-test.yml` — extended in Test D with `testMode` (choice) and `notificationEmail` (string) inputs to enable positive passthrough verification.
- `workflow-orchestration-setup.md` — update separately once the feature is verified.
