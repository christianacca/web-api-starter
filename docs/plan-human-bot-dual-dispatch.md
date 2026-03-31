# Plan: Human + Bot Dual Dispatch for `github-integration-test.yml`

## TL;DR

Make `workflowName` input optional. Its presence signals bot dispatch; its absence signals human dispatch. Guard bot-only jobs (`github-app-authz`, `publish-inprogress`, `publish-completed`, `qa-auto-approve`) with bot-actor conditions. Update environment jobs (`dev-task`, `qa-task`) with `always() && !cancelled()` and dual-condition expressions so they run for both dispatch modes. For human dispatch, `qa-task` is gated by the GitHub environment protection rule (a human must approve). Shared actions are NOT modified. Run E2E verification for both bot and human dispatch paths, then update `workflow-orchestration-setup.md` with guidance based on verified behaviour.

---

## Key design decisions

- **Detection mechanism**: `endsWith(github.triggering_actor, '[bot]')` = bot dispatch; otherwise human dispatch. GitHub sets `triggering_actor` — it cannot be forged via inputs. GitHub App bots always carry a `[bot]` suffix; human accounts never do. Using an input (`workflowName`) as the signal would be a security hole: a bot could omit it and bypass `github-app-authz-envs`.
- **`workflowName` remains optional** so human dispatch works, but it is NOT the dispatch-mode signal. Its presence controls only `run-name` display and is required by `publish-inprogress` for queue context resolution (a bot that omits it will fail at `publish-inprogress`, so env jobs are still gated).
- **Shared actions unmodified**: `github-app-authz-envs` and `publish-github-workflow-event` are NOT changed.
- **`publish-inprogress` skips naturally** when `github-app-authz` is skipped — no explicit `if` needed on that job.
- **`publish-completed` already correct** — guarded by `published-in-progress == 'true'`; when skipped that output is empty, so it naturally skips for human dispatch.
- **Human dispatch runs dev and qa environment jobs** but `qa-auto-approve` is bot-only. For human dispatch, `qa-task` is gated by the GitHub environment protection rule and requires a human reviewer to approve.
- **run-name for human dispatch**: `manual: <github.actor>`

---

## Phase 1: Modify `github-integration-test.yml`

> **Agent instruction**: tick each checkbox in this document (`- [ ]` → `- [x]`) immediately after completing each step. Do not batch ticks at the end.

**File**: `.github/workflows/github-integration-test.yml`

### Steps

- [x] Read `github-integration-test.yml` to confirm current full content before editing.
- [x] Make `workflowName` input optional: remove `required: true`, add `default: ''`.
- [x] Update `run-name`: `${{ inputs.workflowName != '' && inputs.workflowName || format('manual: {0}', github.actor) }}`.
- [x] Add `if: endsWith(github.triggering_actor, '[bot]')` to the `github-app-authz` job. No other change to that job.
- [x] Confirm `publish-inprogress` naturally skips (it has `needs: github-app-authz` with no `always()`, so it is skipped when authz is skipped). No change needed.
- [x] Update `dev-task` `if` condition:
  ```yaml
  if: |
    always() && !cancelled() &&
    (
      !endsWith(github.triggering_actor, '[bot]') ||
      (needs.publish-inprogress.result == 'success' &&
       contains(fromJSON(needs.publish-inprogress.outputs.authz-authorized-target-envs), 'dev'))
    )
  ```
- [x] Update `qa-auto-approve` `if` condition:
  ```yaml
  if: |
    always() && !cancelled() &&
    (
      !endsWith(github.triggering_actor, '[bot]') ||
      (needs.publish-inprogress.result == 'success' &&
       contains(fromJSON(needs.publish-inprogress.outputs.authz-authorized-target-envs), 'qa'))
    )
  ```
- [x] Update `qa-task` `if` condition (same pattern as `qa-auto-approve`):
  ```yaml
  if: |
    always() && !cancelled() &&
    (
      !endsWith(github.triggering_actor, '[bot]') ||
      (needs.publish-inprogress.result == 'success' &&
       contains(fromJSON(needs.publish-inprogress.outputs.authz-authorized-target-envs), 'qa'))
    )
  ```
- [x] Verify `publish-completed` — existing `if: ${{ always() && needs.publish-inprogress.outputs.published-in-progress == 'true' }}` correctly skips for human dispatch (output is empty when job skipped). No change needed unless issues found.
- [x] **Code review checklist** (agent must complete before moving to Phase 2):
  - [x] Are all `needs` declarations correct? `dev-task`, `qa-auto-approve`, `qa-task` still `needs: publish-inprogress` — correct, so authz outputs are accessible for bot dispatch.
  - [x] Does `always()` appear on every environment job that must run even when needs are skipped?
  - [x] Does `!cancelled()` appear on every environment job?
  - [x] Is `run-name` expression valid GitHub Actions expression syntax?
  - [x] No new code references missing variables or outputs that could be null for either dispatch mode?
  - [x] Shared actions `github-app-authz-envs` and `publish-github-workflow-event` are untouched?
  - [x] Confirm security: a bot that deliberately omits `workflowName` still hits `github-app-authz` (actor ends with `[bot]`), then `publish-inprogress` fails (no `workflowName` to resolve `instanceId`), so env jobs are gated on a failed need and do not run.
- [x] **Feed-forward to Phase 2**: Record final `if` conditions for each job and confirm both dispatch paths are ready for E2E testing. Note that the pattern is: bot-only jobs guarded with `endsWith(github.triggering_actor, '[bot]')`; environment jobs use `always() && !cancelled() && (!endsWith(...) || bot-condition)`.

---

## Phase 2: End-to-End Verification

> **Agent instruction**: tick each checkbox in this document (`- [ ]` → `- [x]`) immediately after completing each step. Do not batch ticks at the end.

> **Scenario correspondence**: Sub-phase A = Scenario 2 (bot, dev only), Sub-phase B = Scenario 3 (human), Sub-phase C = Scenario 1 (bot, dev+qa).  
> **Execution order for complete re-verification**: Run Scenario 3 first (no infrastructure required), Scenario 2 second (bot dispatch infra required), Scenario 1 last (requires a temporary change to `get-product-github-app-config.ps1` that must be reverted and committed at the end).

### Sub-phase A: Scenario 2 — Bot dispatch, GitHub App authorized for dev only

Prerequisites: dev tunnel running, Azurite running, Functions app running locally.

- [x] Execute all 12 steps of the "Exact Local E2E Validation Procedure" in `docs/workflow-orchestration-setup.md` verbatim, using four terminal sessions (A: Azurite, B: tunnel, C: Functions, D: commands).
- [x] Verify all 8 pass criteria from the doc:
  - [x] Functions health check `GET /api/Echo` succeeds.
  - [x] Dev tunnel shows active host connection for port 10001.
  - [x] `POST /api/workflow/start` returns a non-empty `instanceId`.
  - [x] GitHub Actions run with `displayTitle == InternalApi-<instanceId>` exists on the target branch.
  - [x] That run reaches `completed`.
  - [x] Functions log contains both `GithubWorkflowInProgress` and `GithubWorkflowCompleted` for the instance.
  - [x] Azurite Durable state exists in both `TestHubNameInstances` and `TestHubNameHistory` for the instance.
  - [x] Terminal Durable state is consistent with the GitHub Actions conclusion.
- [x] On failure: collect `tmp/local-workflow-functions.log`, `tmp/local-workflow-durable-instances.json`, `tmp/local-workflow-durable-history.json`, record failing command and instanceId.
- [x] **Feed-forward to Sub-phase B**: Note whether the GitHub Actions run's `github-app-authz`, `publish-inprogress`, and `publish-completed` jobs all ran (as expected for bot dispatch). If any were unexpectedly skipped, investigate before proceeding.

  > **Feed-forward note**: `github-app-authz` ran (success), `publish-inprogress` ran (success), `publish-completed` ran (success), `dev-task` ran (success). `qa-auto-approve` and `qa-task` were correctly **skipped** because this GitHub App is only authorized for `dev` (not `qa`) — this is the expected, correct behaviour. Also found and fixed a YAML bug: the original `run-name` expression was an unquoted YAML plain scalar containing `': '` (colon-space) from `format('manual: {0}', ...)`, which YAML parsers treat as a mapping separator. Fixed by wrapping the `run-name` value in double quotes.

**Scenario 2 re-run** (after qa-auto-approve redesigned as bot-only):
- [x] Verify infrastructure: Azurite running, dev tunnel active, Functions healthy at `GET http://localhost:7071/api/Echo`.
- [x] Run bot dispatch E2E per the 12-step procedure above and wait for run to complete.
- [x] Verify run conclusion = `success`.
- [x] Verify per-job results: `github-app-authz`=success, `publish-inprogress`=success, `dev-task`=success, `qa-auto-approve`=**skipped** (qa not in authorized-target-envs), `qa-task`=**skipped** (qa not in authorized-target-envs), `publish-completed`=success.
- [x] Verify Durable terminal state: RuntimeStatus=`Completed`.

### Sub-phase B: Scenario 3 — Human dispatch

No Azurite, no dev tunnel, no Functions app required for this sub-phase.

- [x] Confirm current branch is pushed to GitHub:
  ```pwsh
  git push
  ```
- [x] Set variables:
  ```pwsh
  $WorkflowBranch = (git rev-parse --abbrev-ref HEAD).Trim()
  $WorkflowFile = 'github-integration-test.yml'
  $env:GH_PAGER = 'cat'
  ```
- [x] Dispatch the workflow as a human (no `workflowName` input):
  ```pwsh
  gh workflow run $WorkflowFile --ref $WorkflowBranch
  ```
- [x] Wait ~15 seconds then locate the most recent run for this workflow on this branch:
  ```pwsh
  $HumanRuns = gh run list --workflow $WorkflowFile --branch $WorkflowBranch --limit 5 --json databaseId,displayTitle,status,conclusion,createdAt | ConvertFrom-Json
  $LatestHumanRun = $HumanRuns | Sort-Object createdAt -Descending | Select-Object -First 1
  $LatestHumanRun | Select-Object databaseId, displayTitle, status, conclusion, createdAt | Format-List
  ```
- [x] Confirm the run name matches `manual: <actor>` (not `InternalApi-...`).
- [x] Wait for completion (up to 10 minutes):
  ```pwsh
  foreach ($i in 1..60) {
    Start-Sleep -Seconds 10
    $HumanRun = gh run view $LatestHumanRun.databaseId --json databaseId,status,conclusion,url,displayTitle | ConvertFrom-Json
    Write-Host "status: $($HumanRun.status); conclusion: $($HumanRun.conclusion)"
    if ($HumanRun.status -eq 'completed') { break }
  }
  ```
- [x] Verify per-job results:
  ```pwsh
  gh run view $LatestHumanRun.databaseId --json jobs | ConvertFrom-Json | Select-Object -ExpandProperty jobs | Select-Object name, status, conclusion | Format-Table
  ```
  Expected:
  - `github-app-authz` → `skipped`
  - `publish-inprogress` → `skipped`
  - `dev-task` → `success`
  - `qa-auto-approve` → `skipped` (bot-only; human dispatch hits the GitHub environment protection gate instead)
  - `qa-task` → `success` (after a human approves the qa environment gate)
  - `publish-completed` → `skipped`
- [x] Confirm no unexpected queue messages were published (no Durable instance created for this run):
  - No `InternalApi-...` run name was created.
  - No Functions app was involved.
- [x] **Final review checklist**:
  - [x] Did both dispatch paths complete successfully?
  - [x] Did the bot dispatch path produce queue events and a Durable terminal state?
  - [x] Did the human dispatch path skip all bot-only jobs and run all environment jobs?
  - [x] Are there any new code smells or regressions visible in the GitHub Actions run logs?
- [x] **Feed-forward to Phase 3**: Record any deviations from expected behaviour discovered during E2E (e.g. unexpected job skip/run, wrong run name format, authz failures). Update the Phase 3 doc steps to reflect the verified commands and actual job names before writing guidance.

  > **Feed-forward note (initial run)**: Initial run result: `github-app-authz`=skipped, `publish-inprogress`=skipped, `dev-task`=success, `qa-auto-approve`=success (at that time the job used a dual-condition that also ran for human dispatch), `qa-task`=success, `publish-completed`=skipped. Run name `manual: christianacca` matched the pattern. No queue messages or Durable instances were created. **Post-run change**: `qa-auto-approve` was subsequently redesigned to be bot-only, so Scenario 3 requires a re-run to confirm the new expected behaviour. **YAML bug found and fixed**: the `run-name` expression must be double-quoted in YAML because `format('manual: {0}', ...)` contains `': '` (colon-space) which YAML interprets as a mapping separator.

**Scenario 3 re-run** (confirming qa-auto-approve is now **skipped** for human dispatch):

- [x] Push current branch: `git push`
- [x] Dispatch the workflow as a human (no `workflowName` input):
  ```pwsh
  $WorkflowBranch = (git rev-parse --abbrev-ref HEAD).Trim()
  $env:GH_PAGER = 'cat'
  gh workflow run github-integration-test.yml --ref $WorkflowBranch
  ```
- [x] Wait ~15 seconds then locate the latest run:
  ```pwsh
  $HumanRuns = gh run list --workflow github-integration-test.yml --branch $WorkflowBranch --limit 5 --json databaseId,displayTitle,status,conclusion,createdAt | ConvertFrom-Json
  $LatestRun = $HumanRuns | Sort-Object createdAt -Descending | Select-Object -First 1
  $LatestRun | Select-Object databaseId, displayTitle, status, conclusion | Format-List
  ```
- [x] Confirm run-name = `manual: <actor>`.
- [x] Wait for `dev-task` to complete, then approve the `qa` environment gate so `qa-task` can proceed:
  ```pwsh
  $QaEnvId = (gh api "repos/christianacca/web-api-starter/environments" | ConvertFrom-Json).environments |
      Where-Object { $_.name -eq 'qa' } | Select-Object -ExpandProperty id
  gh api "repos/christianacca/web-api-starter/actions/runs/$($LatestRun.databaseId)/pending_deployments" `
      --method POST -F "environment_ids[]=$QaEnvId" -f state=approved -f comment="Scenario 3 re-run verification"
  ```
- [x] Wait for run to complete and verify per-job results:
  ```pwsh
  gh run view $LatestRun.databaseId --json jobs | ConvertFrom-Json |
      Select-Object -ExpandProperty jobs | Select-Object name, status, conclusion | Format-Table
  ```
  Expected:
  - `github-app-authz` → `skipped`
  - `publish-inprogress` → `skipped`
  - `dev-task` → `success`
  - `qa-auto-approve` → **`skipped`** (bot-only; no auto-approve for human dispatch)
  - `qa-task` → `success` (after approval above)
  - `publish-completed` → `skipped`
- [x] Confirm no Durable instance created for this run.

### Sub-phase C: Scenario 1 — Bot dispatch, GitHub App authorized for dev AND qa

> **Critical**: The change to `get-product-github-app-config.ps1` in this sub-phase is a real authorization change. It **must** be reverted and the revert committed before merging the branch.

Prerequisites: Azurite running, dev tunnel active, Functions app running locally. If infra has been stopped, restart it before proceeding.

- [x] Modify `get-product-github-app-config.ps1` line 13: change `Pipeline = @('dev')` to `Pipeline = @('dev', 'qa')`.
- [x] Commit and push the temporary change:
  ```pwsh
  git add tools/infrastructure/get-product-github-app-config.ps1
  git commit -m "temp: authorize GitHub App for qa (Scenario 1 E2E — revert before merge)"
  git push
  ```
- [x] Run bot dispatch E2E per the 12-step procedure in Sub-phase A. Wait for the run to complete.
- [x] Verify run conclusion = `success`.
- [x] Verify per-job results:
  ```pwsh
  gh run view $RunId --json jobs | ConvertFrom-Json |
      Select-Object -ExpandProperty jobs | Select-Object name, status, conclusion | Format-Table
  ```
  Expected:
  - `github-app-authz` → `success`
  - `publish-inprogress` → `success`
  - `dev-task` → `success`
  - `qa-auto-approve` → `success` (bot dispatch + qa in authorized-target-envs)
  - `qa-task` → `success` (gate auto-approved by qa-auto-approve above)
  - `publish-completed` → `success`
- [x] Verify Durable terminal state: RuntimeStatus = `Completed`.
- [x] Verify Functions log contains both `GithubWorkflowInProgress` and `GithubWorkflowCompleted` for the instance.
- [x] **Revert** `get-product-github-app-config.ps1` to `Pipeline = @('dev')`:
  ```pwsh
  git revert HEAD --no-edit
  git push
  ```
- [x] Confirm `get-product-github-app-config.ps1` line 13 = `Pipeline = @('dev')`.

---

## Phase 3: Update `workflow-orchestration-setup.md`

> **Agent instruction**: tick each checkbox in this document (`- [ ]` → `- [x]`) immediately after completing each step. Do not batch ticks at the end.

**File**: `docs/workflow-orchestration-setup.md`

### Scope boundary — what NOT to do

> **Agent instruction**: Before writing a single word, read this boundary carefully. The two failure modes to avoid are:
>
> 1. **Over-complicating the existing minimal example** — the `github-integration-test.yml` workflow is a complex dual-dispatch example. The "Workflow Requirements" minimal example in the doc must remain bot-only and simple. Do **not** add dual-dispatch `if` conditions to it.
> 2. **Failing to acknowledge the example** — the doc must make it clear that `github-integration-test.yml` IS the canonical reference for dual-dispatch patterns, so readers know it exists without having to reproduce its complexity in prose.
>
> The right line to tread: explain the **concept and detection mechanism** concisely, show short **pattern snippets** only (not a full workflow template), and point to `github-integration-test.yml` for the complete implementation. The inline comments within that file are self-documenting — the doc should guide readers there rather than duplicate that information.

### Steps

- [x] Re-read `workflow-orchestration-setup.md` to confirm the position of "Workflow Requirements" and "Authorization Contract" sections and identify the correct insertion point for the new section.
- [x] Add a new section **"Supporting Both Human and Bot Dispatch"** between "Workflow Requirements" and "Authorization Contract". The section must cover:
  - **Problem statement**: by default the authz and queue-publishing jobs are bot-only; a workflow that needs to support human dispatch must explicitly detect the dispatch mode.
  - **Detection pattern**: `endsWith(github.triggering_actor, '[bot]')` is the secure signal — GitHub sets `triggering_actor`, so it cannot be forged via inputs. Briefly explain why using `workflowName != ''` would be insecure.
  - **Two short pattern snippets only** (not a full workflow template):
    1. Bot-only guard (for `github-app-authz` and other skippable-by-humans jobs): `if: endsWith(github.triggering_actor, '[bot]')`
    2. Dual-condition pattern (for environment jobs that must run for both modes): the `always() && !cancelled() && (!endsWith([bot]) || bot-condition)` template.
  - **Reference to `github-integration-test.yml`** as the canonical full implementation, with a sentence noting that the workflow's inline comments document each job's behaviour for each dispatch scenario.
  - **Note that `workflowName` becomes optional** when supporting human dispatch, and that `run-name` should handle the empty case (e.g. `format('manual: {0}', github.actor)`). Add the YAML quoting requirement: the `run-name` value **must be double-quoted** when the expression contains `': '` (colon-space), otherwise YAML interprets it as a mapping separator.
  - **Note that shared actions are NOT modified**: `github-app-authz-envs` and `publish-github-workflow-event` work unchanged for both dispatch modes.
- [x] Add a new sibling section **"Human Dispatch Simulation"** immediately after the "Exact Local E2E Validation Procedure" section. This section is specifically about verifying `github-integration-test.yml` and must make that scope explicit. It covers:
  - **Purpose**: verify that, for a human-triggered run of `github-integration-test.yml`, bot-only jobs are skipped and environment jobs still run without queue interaction.
  - **No infrastructure required**: no tunnel, no Azurite, no Functions app.
  - **Terminal commands**: push branch, dispatch via `gh workflow run github-integration-test.yml --ref <branch>` (no inputs), locate run, poll for completion, approve the `qa` environment gate.
  - **Pass criteria** (framed as specific to `github-integration-test.yml`, not as a general contract): `github-app-authz`=skipped, `publish-inprogress`=skipped, `dev-task`=success, `qa-auto-approve`=skipped, `qa-task`=success (after human approval), `publish-completed`=skipped; run-name = `manual: <actor>`; no Durable instance created.
  - **Approval step**: include the `gh api .../pending_deployments` POST command with `state=approved` to unblock `qa-task`, since the qa environment gate requires a reviewer.
- [x] **Code review checklist**:
  - [x] Does the "Supporting Both Human and Bot Dispatch" section stay at the concept+snippet level, with no full workflow template embedded?
  - [x] Does the existing "Workflow Requirements" minimal example remain unchanged (bot-only, simple `workflowName` required)?
  - [x] Does `github-integration-test.yml` appear as a named reference, not as an inline duplication?
  - [x] Do the pattern snippets match exactly what is implemented in Phase 1?
  - [x] Is the "Human Dispatch Simulation" section clearly scoped to `github-integration-test.yml` and not presented as a generic procedure?
  - [x] Is the human dispatch simulation procedure self-contained (no cross-references to the bot E2E steps for infrastructure)?
- [x] **Consistency check**: Confirm pattern snippets match exactly the `if` conditions in `github-integration-test.yml`. Confirm simulation commands match what was executed in Phase 2 Sub-phase B (Scenario 3 re-run).

---

## Relevant files

- `.github/workflows/github-integration-test.yml` — primary file to modify; uses `github-app-authz` → `publish-inprogress` → env-jobs → `publish-completed` chain
- `.github/actions/github-app-authz-envs/action.yml` — READ ONLY; understand outputs (`primary`, `pipeline`, `authorized-target-envs`, `installation-id`)
- `.github/actions/publish-github-workflow-event/action.yml` — READ ONLY; understand the `published` output used by `publish-completed`
- `docs/workflow-orchestration-setup.md` — add "Supporting Both Human and Bot Dispatch" section and human dispatch simulation steps

## Scope

**Included**: `github-integration-test.yml` changes, doc guidance, E2E bot + human verification.  
**Excluded**: Modifications to `github-app-authz-envs`, `publish-github-workflow-event`, or any other workflow files.
