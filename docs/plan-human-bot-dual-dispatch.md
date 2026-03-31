# Plan: Human + Bot Dual Dispatch for `github-integration-test.yml`

## TL;DR

Make `workflowName` input optional. Its presence signals bot dispatch; its absence signals human dispatch. Guard bot-only jobs (`github-app-authz`, `publish-inprogress`, `publish-completed`) with `if: endsWith(github.triggering_actor, '[bot]')`. Update environment jobs (`dev-task`, `qa-auto-approve`, `qa-task`) with `always() && !cancelled()` and dual-condition expressions so they run for both dispatch modes. Shared actions are NOT modified. Run E2E verification for both bot and human dispatch paths, then update `workflow-orchestration-setup.md` with guidance based on verified behaviour.

---

## Key design decisions

- **Detection mechanism**: `endsWith(github.triggering_actor, '[bot]')` = bot dispatch; otherwise human dispatch. GitHub sets `triggering_actor` — it cannot be forged via inputs. GitHub App bots always carry a `[bot]` suffix; human accounts never do. Using an input (`workflowName`) as the signal would be a security hole: a bot could omit it and bypass `github-app-authz-envs`.
- **`workflowName` remains optional** so human dispatch works, but it is NOT the dispatch-mode signal. Its presence controls only `run-name` display and is required by `publish-inprogress` for queue context resolution (a bot that omits it will fail at `publish-inprogress`, so env jobs are still gated).
- **Shared actions unmodified**: `github-app-authz-envs` and `publish-github-workflow-event` are NOT changed.
- **`publish-inprogress` skips naturally** when `github-app-authz` is skipped — no explicit `if` needed on that job.
- **`publish-completed` already correct** — guarded by `published-in-progress == 'true'`; when skipped that output is empty, so it naturally skips for human dispatch.
- **Human dispatch runs all gated environments** (dev + qa) with `qa-auto-approve` still running (full unattended pipeline).
- **run-name for human dispatch**: `manual: <github.actor>`

---

## Phase 1: Modify `github-integration-test.yml`

**File**: `.github/workflows/github-integration-test.yml`

### Steps

- [ ] Read `github-integration-test.yml` to confirm current full content before editing.
- [ ] Make `workflowName` input optional: remove `required: true`, add `default: ''`.
- [ ] Update `run-name`: `${{ inputs.workflowName != '' && inputs.workflowName || format('manual: {0}', github.actor) }}`.
- [ ] Add `if: endsWith(github.triggering_actor, '[bot]')` to the `github-app-authz` job. No other change to that job.
- [ ] Confirm `publish-inprogress` naturally skips (it has `needs: github-app-authz` with no `always()`, so it is skipped when authz is skipped). No change needed.
- [ ] Update `dev-task` `if` condition:
  ```yaml
  if: |
    always() && !cancelled() &&
    (
      !endsWith(github.triggering_actor, '[bot]') ||
      (needs.publish-inprogress.result == 'success' &&
       contains(fromJSON(needs.publish-inprogress.outputs.authz-authorized-target-envs), 'dev'))
    )
  ```
- [ ] Update `qa-auto-approve` `if` condition:
  ```yaml
  if: |
    always() && !cancelled() &&
    (
      !endsWith(github.triggering_actor, '[bot]') ||
      (needs.publish-inprogress.result == 'success' &&
       contains(fromJSON(needs.publish-inprogress.outputs.authz-authorized-target-envs), 'qa'))
    )
  ```
- [ ] Update `qa-task` `if` condition (same pattern as `qa-auto-approve`):
  ```yaml
  if: |
    always() && !cancelled() &&
    (
      !endsWith(github.triggering_actor, '[bot]') ||
      (needs.publish-inprogress.result == 'success' &&
       contains(fromJSON(needs.publish-inprogress.outputs.authz-authorized-target-envs), 'qa'))
    )
  ```
- [ ] Verify `publish-completed` — existing `if: ${{ always() && needs.publish-inprogress.outputs.published-in-progress == 'true' }}` correctly skips for human dispatch (output is empty when job skipped). No change needed unless issues found.
- [ ] **Code review checklist** (agent must complete before moving to Phase 2):
  - [ ] Are all `needs` declarations correct? `dev-task`, `qa-auto-approve`, `qa-task` still `needs: publish-inprogress` — correct, so authz outputs are accessible for bot dispatch.
  - [ ] Does `always()` appear on every environment job that must run even when needs are skipped?
  - [ ] Does `!cancelled()` appear on every environment job?
  - [ ] Is `run-name` expression valid GitHub Actions expression syntax?
  - [ ] No new code references missing variables or outputs that could be null for either dispatch mode?
  - [ ] Shared actions `github-app-authz-envs` and `publish-github-workflow-event` are untouched?
  - [ ] Confirm security: a bot that deliberately omits `workflowName` still hits `github-app-authz` (actor ends with `[bot]`), then `publish-inprogress` fails (no `workflowName` to resolve `instanceId`), so env jobs are gated on a failed need and do not run.
- [ ] **Feed-forward to Phase 2**: Record final `if` conditions for each job and confirm both dispatch paths are ready for E2E testing. Note that the pattern is: bot-only jobs guarded with `endsWith(github.triggering_actor, '[bot]')`; environment jobs use `always() && !cancelled() && (!endsWith(...) || bot-condition)`.

---

## Phase 2: End-to-End Verification

### Sub-phase A: Bot Dispatch (existing E2E procedure)

Prerequisites: dev tunnel running, Azurite running, Functions app running locally.

- [ ] Execute all 12 steps of the "Exact Local E2E Validation Procedure" in `docs/workflow-orchestration-setup.md` verbatim, using four terminal sessions (A: Azurite, B: tunnel, C: Functions, D: commands).
- [ ] Verify all 8 pass criteria from the doc:
  - [ ] Functions health check `GET /api/Echo` succeeds.
  - [ ] Dev tunnel shows active host connection for port 10001.
  - [ ] `POST /api/workflow/start` returns a non-empty `instanceId`.
  - [ ] GitHub Actions run with `displayTitle == InternalApi-<instanceId>` exists on the target branch.
  - [ ] That run reaches `completed`.
  - [ ] Functions log contains both `GithubWorkflowInProgress` and `GithubWorkflowCompleted` for the instance.
  - [ ] Azurite Durable state exists in both `TestHubNameInstances` and `TestHubNameHistory` for the instance.
  - [ ] Terminal Durable state is consistent with the GitHub Actions conclusion.
- [ ] On failure: collect `tmp/local-workflow-functions.log`, `tmp/local-workflow-durable-instances.json`, `tmp/local-workflow-durable-history.json`, record failing command and instanceId.
- [ ] **Feed-forward to Sub-phase B**: Note whether the GitHub Actions run's `github-app-authz`, `publish-inprogress`, and `publish-completed` jobs all ran (as expected for bot dispatch). If any were unexpectedly skipped, investigate before proceeding.

### Sub-phase B: Human Dispatch Simulation

No Azurite, no dev tunnel, no Functions app required for this sub-phase.

- [ ] Confirm current branch is pushed to GitHub:
  ```pwsh
  git push
  ```
- [ ] Set variables:
  ```pwsh
  $WorkflowBranch = (git rev-parse --abbrev-ref HEAD).Trim()
  $WorkflowFile = 'github-integration-test.yml'
  $env:GH_PAGER = 'cat'
  ```
- [ ] Dispatch the workflow as a human (no `workflowName` input):
  ```pwsh
  gh workflow run $WorkflowFile --ref $WorkflowBranch
  ```
- [ ] Wait ~15 seconds then locate the most recent run for this workflow on this branch:
  ```pwsh
  $HumanRuns = gh run list --workflow $WorkflowFile --branch $WorkflowBranch --limit 5 --json databaseId,displayTitle,status,conclusion,createdAt | ConvertFrom-Json
  $LatestHumanRun = $HumanRuns | Sort-Object createdAt -Descending | Select-Object -First 1
  $LatestHumanRun | Select-Object databaseId, displayTitle, status, conclusion, createdAt | Format-List
  ```
- [ ] Confirm the run name matches `manual: <actor>` (not `InternalApi-...`).
- [ ] Wait for completion (up to 10 minutes):
  ```pwsh
  foreach ($i in 1..60) {
    Start-Sleep -Seconds 10
    $HumanRun = gh run view $LatestHumanRun.databaseId --json databaseId,status,conclusion,url,displayTitle | ConvertFrom-Json
    Write-Host "status: $($HumanRun.status); conclusion: $($HumanRun.conclusion)"
    if ($HumanRun.status -eq 'completed') { break }
  }
  ```
- [ ] Verify per-job results:
  ```pwsh
  gh run view $LatestHumanRun.databaseId --json jobs | ConvertFrom-Json | Select-Object -ExpandProperty jobs | Select-Object name, status, conclusion | Format-Table
  ```
  Expected:
  - `github-app-authz` → `skipped`
  - `publish-inprogress` → `skipped`
  - `dev-task` → `success`
  - `qa-auto-approve` → `success`
  - `qa-task` → `success`
  - `publish-completed` → `skipped`
- [ ] Confirm no unexpected queue messages were published (no Durable instance created for this run):
  - No `InternalApi-...` run name was created.
  - No Functions app was involved.
- [ ] **Final review checklist**:
  - [ ] Did both dispatch paths complete successfully?
  - [ ] Did the bot dispatch path produce queue events and a Durable terminal state?
  - [ ] Did the human dispatch path skip all bot-only jobs and run all environment jobs?
  - [ ] Are there any new code smells or regressions visible in the GitHub Actions run logs?
- [ ] **Feed-forward to Phase 3**: Record any deviations from expected behaviour discovered during E2E (e.g. unexpected job skip/run, wrong run name format, authz failures). Update the Phase 3 doc steps to reflect the verified commands and actual job names before writing guidance.

---

## Phase 3: Update `workflow-orchestration-setup.md`

**File**: `docs/workflow-orchestration-setup.md`

### Steps

- [ ] Re-read `workflow-orchestration-setup.md` to identify the best insertion point (likely after "Workflow Requirements" section, before or within "Authorization Contract").
- [ ] Add a new section **"Supporting Both Human and Bot Dispatch"** that covers:
  - The problem statement: authz + queue publishing must be skipped for human dispatch.
  - The detection pattern: `endsWith(github.triggering_actor, '[bot]')` signals bot dispatch. Explain why input-based detection (`workflowName != ''`) is insecure — a bot controls its own inputs.
  - A table or list of which jobs are bot-only vs universal.
  - The job-level `if` condition templates (both the guard pattern for bot-only jobs and the dual-condition pattern for environment jobs).
  - Reference `github-integration-test.yml` as the canonical implementation example.
  - Note that shared actions `github-app-authz-envs` and `publish-github-workflow-event` are NOT modified.
- [ ] Add a new sub-section within "Exact Local E2E Validation Procedure" (or as a sibling section) titled **"Human Dispatch Simulation"** that covers:
  - Purpose: validate that authz and queue-publishing jobs are skipped and environment jobs still run.
  - No tunnel, no Azurite, no Functions app required.
  - Terminal commands (PowerShell): `gh workflow run github-integration-test.yml --ref <branch>` (no `workflowName` input).
  - How to locate and watch the run: `gh run list --workflow github-integration-test.yml --branch <branch> --limit 5 --json databaseId,displayTitle,status,conclusion | ConvertFrom-Json`.
  - Pass criteria: `github-app-authz` → skipped, `publish-inprogress` → skipped, `dev-task` → success, `qa-auto-approve` → success, `qa-task` → success, `publish-completed` → skipped.
- [ ] **Code review checklist**:
  - [ ] Does the new guidance reference the correct job names and output names?
  - [ ] Are the `if` condition templates accurate as written (consistent with what was implemented in Phase 1)?
  - [ ] Is the human dispatch simulation procedure self-contained?
  - [ ] Are there no references to webhook or HMAC that might now be outdated?
- [ ] **Consistency check**: Confirm the `if` condition templates written in the doc match exactly what was implemented in Phase 1 and verified in Phase 2. Confirm the human dispatch simulation commands match what was executed in Phase 2 Sub-phase B.

---

## Relevant files

- `.github/workflows/github-integration-test.yml` — primary file to modify; uses `github-app-authz` → `publish-inprogress` → env-jobs → `publish-completed` chain
- `.github/actions/github-app-authz-envs/action.yml` — READ ONLY; understand outputs (`primary`, `pipeline`, `authorized-target-envs`, `installation-id`)
- `.github/actions/publish-github-workflow-event/action.yml` — READ ONLY; understand the `published` output used by `publish-completed`
- `docs/workflow-orchestration-setup.md` — add "Supporting Both Human and Bot Dispatch" section and human dispatch simulation steps

## Scope

**Included**: `github-integration-test.yml` changes, doc guidance, E2E bot + human verification.  
**Excluded**: Modifications to `github-app-authz-envs`, `publish-github-workflow-event`, or any other workflow files.
