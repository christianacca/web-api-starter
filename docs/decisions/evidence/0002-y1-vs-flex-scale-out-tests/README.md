# Function App Scale-Out Test: Y1 Content-Share Removal

## Why this test exists

`web-api-starter` currently runs its Functions app (`func-clc-was-dev-internalapi`) on the
Windows **Y1 Consumption** plan, with the deployment package delivered via the classic
Azure Files content-share (`WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` /
`WEBSITE_CONTENTSHARE`). We stayed on Y1 (rather than moving to Flex Consumption) mainly
for cost reasons, but the concern that keeps coming back is whether Y1 can still scale
out new instances reliably once we remove the Azure Files connection string in favor of
managed identity + `WEBSITE_RUN_FROM_PACKAGE` (blob URL).

This repo is the scaffolding/template for `data-services-gateway` (DSG). DSG has an
analogous Y1 Functions app doing real work (Durable Functions orchestrating Power BI
workspace deployment and dataset refresh), so we don't want to test the content-share
change there directly — it has real side effects. Instead we validate the change here
first, using a simple burst-load script, then port the change to DSG once we're
confident scale-out behavior is unaffected.

## What we're testing and why

We considered building a synthetic Durable Function orchestration in this repo to more
closely mirror DSG's `DeploymentOrchestrator` / `DatasetRefreshOrchestrator` shape, but
decided against it: the specific mechanism at risk from removing the content-share is
Consumption-plan **instance specialization / package loading during scale-out** — a
plain queue-trigger burst exercises that exact mechanism. Durable Functions add extra
scaling nuances (e.g. control-queue partitioning) that are orthogonal to the
content-share change and would show up identically in both the before/after runs, so
they wouldn't change the comparison. A plain HTTP + Queue burst is enough to answer the
question.

Two signals, for two different reasons:

- **Queue burst** (direct AAD-token REST POST to the `default-queue` Storage Queue,
  bypassing the API entirely) — the **primary signal**. It triggers `ExampleQueue.cs`'s
  no-op `SimpleMessage` case and isn't bottlenecked by anything except the Functions
  scale controller, so it's the cleanest measure of how fast/reliably new Function App
  instances come online under load.
- **HTTP burst** (`GET /api/Echo`, proxied through the API container app to the Function
  App's `GetEcho.cs`) — a **secondary signal**. The API container app (`ca-was-dev-eus2-api`)
  has `MinReplicas: 0, MaxReplicas: 2`, so at high concurrency the API itself can become
  the bottleneck rather than the Function App. Useful as a sanity check, but the queue
  burst is the one to trust for the actual scale-out decision.

Both bursts hit real, already-existing, side-effect-free endpoints — no new
infrastructure, no synthetic orchestrations.

## Script

`web-api-starter/tools/dev-scripts/Test-FunctionScaleOut.ps1`

```powershell
pwsh -NoProfile -File ./Test-FunctionScaleOut.ps1 `
  -Label <run-label> `
  -Mode Both `
  -HttpConcurrency 50 -HttpDurationSeconds 90 `
  -QueueMessageCount 500 -QueueConcurrency 50
```

(run from `web-api-starter/tools/dev-scripts`)

- Resolves environment conventions (API hostname, Function App name, storage account,
  App Insights workspace) dynamically via `tools/infrastructure/get-product-conventions.ps1`
  — never hardcoded.
- Warms up the API + Function App with 3 sequential Echo calls before timing starts, so
  the API container app's own cold start (`MinReplicas: 0`) doesn't pollute the
  measurement.
- `dev` has a single region (`eastus2`) — no secondary/DR region to worry about hitting
  by mistake.
- Emits, per run, into `output/scale-tests/<timestamp>-<label>/`:
  - `summary.json` — totals/failures/time windows for both bursts
  - `http-burst-results.csv`, `queue-burst-results.csv` — per-request timing/status
  - `kql-queries.kql` — ready-to-paste Log Analytics queries (workspace `log-was-dev`,
    `AppRoleName == "Web API Starter Functions"`) for instance ramp-up curve,
    time-to-first-additional-instance, and latency percentiles

### Bug found and fixed while validating the script

The first baseline run (`baseline-contentshare`, since deleted/superseded) used
PascalCase JSON keys (`Id`, `Data`, `Metadata`, `MessageType`) for the synthetic queue
messages. The app's `JsonSerializerOptions` are configured with
`PropertyNamingPolicy = JsonNamingPolicy.CamelCase`
(`Template.Shared/Extensions/JsonSerializationOptionsExtensions.cs`), so
`ExampleQueue.RunAsync` deserialized every message with `Data = ""` and
`Metadata.MessageType = ""`, which fails `[Required]` validation
(`Template.Shared/Azure/MessageQueue/MessageBody.cs`) — **every one of the 500 queue
messages in that run failed on all 5 delivery attempts** (`QueueConstants.MaxDequeueCount`),
for 2,500 failed `ExampleQueue` invocations, even though the enqueue calls themselves
all reported success. The `queue-burst-results.csv`/`summary.json` only ever tracked the
enqueue call succeeding, not the function's actual processing outcome, so this was silent
until checked against `AppExceptions` in Log Analytics.

**Fixed** in `Test-FunctionScaleOut.ps1`'s `Invoke-QueueBurst`: message body now uses
camelCase keys (`id`, `data`, `metadata.messageType`). Also fixed the script's emitted
`kql-queries.kql` to use the correct schema for this workspace — it's **workspace-based
Application Insights**, so the table/columns are `AppRequests` /
`TimeGenerated` / `AppRoleName` / `AppRoleInstance` / `DurationMs` / `Success` /
`Name`, not the classic `requests` / `timestamp` / `cloud_RoleName` /
`cloud_RoleInstance` / `duration` / `success` / `name` schema the script originally emitted.
All results below are from the corrected run and corrected queries.

## Baseline run (before: still on Azure Files content-share)

Run against the current `master` deployment in dev (content-share still in place),
from `web-api-starter/tools/dev-scripts`:

```powershell
pwsh -NoProfile -File ./Test-FunctionScaleOut.ps1 -Label baseline-contentshare-v2 -Mode Both `
  -HttpConcurrency 50 -HttpDurationSeconds 90 -QueueMessageCount 500 -QueueConcurrency 50
```

Artifacts: [`20260924-131036-baseline-contentshare-v2/`](./runs/20260924-131036-baseline-contentshare-v2/)

### Summary

| Burst | Total                       | Failures    | Window (UTC)                                                                     |
| ----- | --------------------------- | ----------- | -------------------------------------------------------------------------------- |
| HTTP  | 6,567 requests              | 0 (all 200) | 07:40:52.218 -> 07:42:30.634 (~98s)                                              |
| Queue | 500 enqueued, 500 processed | 0           | enqueue 07:42:32.438 -> 07:42:41.880 (~9.4s); processing drained by 07:42:43.928 |

### HTTP burst - instance ramp-up + latency, 10s bins

Query (workspace `log-was-dev`):

```kql
AppRequests
| where TimeGenerated between (datetime(2026-09-24T07:40:52.2180552Z) .. datetime(2026-09-24T07:42:30.6343544Z))
| where AppRoleName == "Web API Starter Functions"
| summarize instanceCount = dcount(AppRoleInstance), reqCount = count(), p50 = percentile(DurationMs, 50), p95 = percentile(DurationMs, 95), p99 = percentile(DurationMs, 99), failures = countif(Success == false) by bin(TimeGenerated, 10s)
| order by TimeGenerated asc
```

Result:

| TimeGenerated (UTC) | InstanceCount | ReqCount | P50 (ms) | P95 (ms) | P99 (ms) | Failures |
| ------------------- | ------------- | -------- | -------- | -------- | -------- | -------- |
| 07:40:50            | 4             | 93       | 90.44    | 5,097.41 | 5,626.28 | 0        |
| 07:41:00            | 4             | 510      | 33.62    | 106.86   | 157.40   | 0        |
| 07:41:10            | 4             | 586      | 38.01    | 100.47   | 161.52   | 0        |
| 07:41:20            | 4             | 818      | 24.89    | 78.24    | 105.92   | 0        |
| 07:41:30            | 4             | 826      | 24.76    | 71.79    | 103.12   | 0        |
| 07:41:40            | 4             | 846      | 22.87    | 56.14    | 77.86    | 0        |
| 07:41:50            | 4             | 817      | 22.74    | 65.49    | 86.95    | 0        |
| 07:42:00            | 4             | 854      | 20.52    | 56.83    | 77.87    | 0        |
| 07:42:10            | 4             | 830      | 26.12    | 62.65    | 75.10    | 0        |
| 07:42:20            | 4             | 385      | 26.34    | 62.50    | 91.36    | 0        |

**Note**: instance count is flat at 4 for the whole window because 4 instances were
already warm from the 3-request warmup immediately preceding the burst (see
"first-seen per instance" below - all 4 came online within ~1.7s of the burst
starting, which is itself the interesting signal). The only elevated latency bin is
the very first 10s window (P95 5.1s / P99 5.6s on 93 requests) - consistent with
those last few instances finishing cold start/specialization while already receiving
traffic. After that everything settles to single/double-digit millisecond P50 and P95
well under 110ms.

### HTTP burst - first-seen per instance (ramp-up speed)

Query:

```kql
AppRequests
| where TimeGenerated between (datetime(2026-09-24T07:40:52.2180552Z) .. datetime(2026-09-24T07:42:30.6343544Z))
| where AppRoleName == "Web API Starter Functions"
| summarize firstSeen = min(TimeGenerated) by AppRoleInstance
| order by firstSeen asc
```

Result:

| AppRoleInstance (truncated) | FirstSeen (UTC) |
| --------------------------- | --------------- |
| fcb9ef26939ff2...           | 07:40:54.860    |
| dfb28dc690fbcc...           | 07:40:56.382    |
| a923c053f98739...           | 07:40:56.433    |
| e7c54834c3326d...           | 07:40:56.583    |

All 4 instances online within **1.72s** of burst start.

### Queue burst - instance ramp-up + drain, 10s bins

Query:

```kql
AppRequests
| where TimeGenerated > datetime(2026-09-24T07:42:32.4375817Z)
| where AppRoleName == "Web API Starter Functions"
| where Name has "ExampleQueue" and Name !has "ExceptionHandler"
| summarize instanceCount = dcount(AppRoleInstance), invocationCount = count(), succeeded = countif(Success == true), failed = countif(Success == false), lastSeen = max(TimeGenerated) by bin(TimeGenerated, 10s)
| order by TimeGenerated asc
```

Result:

| TimeGenerated (UTC) | InstanceCount | InvocationCount | Succeeded | Failed | LastSeen (UTC) |
| ------------------- | ------------- | --------------- | --------- | ------ | -------------- |
| 07:42:30            | 1             | 256             | 256       | 0      | 07:42:39.972   |
| 07:42:40            | 5             | 244             | 244       | 0      | 07:42:43.928   |

All 500 messages processed successfully on first attempt, 0 failures. Instance count
rose from 1 (still warm from the HTTP burst that ended ~2s earlier) to 5 as the queue
length spiked. Drain time (last invocation minus first enqueue): 07:42:43.928 minus
07:42:32.438 = **~11.5s** for 500 messages.

### Queue burst - processing latency percentiles

Query:

```kql
AppRequests
| where TimeGenerated > datetime(2026-09-24T07:42:32.4375817Z)
| where AppRoleName == "Web API Starter Functions"
| where Name has "ExampleQueue" and Name !has "ExceptionHandler"
| summarize total = count(), p50 = percentile(DurationMs, 50), p95 = percentile(DurationMs, 95), p99 = percentile(DurationMs, 99), min(DurationMs), max(DurationMs)
```

Result:

| Total | P50 (ms) | P95 (ms) | P99 (ms) | Min (ms) | Max (ms) |
| ----- | -------- | -------- | -------- | -------- | -------- |
| 500   | 32.21    | 378.89   | 598.84   | 8.64     | 696.09   |

### Notable pattern to re-check in the "after" run

The raw `http-burst-results.csv` (client-observed elapsed time, not the server-side
`DurationMs` above) shows a recurring cluster of ~15,500-15,900ms-latency requests
(still 200 OK) roughly every 2.5-5s throughout the run, against a baseline of
500-900ms for the bulk of client-observed requests. This is a client-side
(API-container-app-hop) latency signature, not visible in the Function App's own
`DurationMs` numbers above - worth comparing cadence/magnitude in the after-run since
a regression there would be a signal against the content-share removal, but it's more
likely attributable to the API container app's own `MaxReplicas: 2` cap than to the
Function App change under test.

## After run (managed identity, content-share removed)

Run against branch `sb/function-connection-string` deployed to dev (content-share
settings removed, `WEBSITE_RUN_FROM_PACKAGE` now points at the blob URL, managed
identity used for `AzureWebJobsStorage`), from `web-api-starter/tools/dev-scripts`:

```powershell
pwsh -NoProfile -File ./Test-FunctionScaleOut.ps1 -Label after-managed-identity -Mode Both `
  -HttpConcurrency 50 -HttpDurationSeconds 90 -QueueMessageCount 500 -QueueConcurrency 50
```

Artifacts: [`20260924-144604-after-managed-identity/`](./runs/20260924-144604-after-managed-identity/)

### Summary

| Burst | Total                       | Failures    | Window (UTC)                                                        |
| ----- | --------------------------- | ----------- | ------------------------------------------------------------------- |
| HTTP  | 5,973 requests              | 0 (all 200) | 09:16:26.112 -> 09:18:10.200 (~104s)                                |
| Queue | 500 enqueued, 500 processed | 0           | enqueue 09:18:12.506 -> processing drained by 09:18:24.607 (~12.1s) |

### HTTP burst - instance ramp-up + latency, 10s bins

Query (workspace `log-was-dev`):

```kql
AppRequests
| where TimeGenerated between (datetime(2026-09-24T09:16:26.1120737Z) .. datetime(2026-09-24T09:18:10.1997206Z))
| where AppRoleName == "Web API Starter Functions"
| summarize instanceCount = dcount(AppRoleInstance), reqCount = count(), p50 = percentile(DurationMs, 50), p95 = percentile(DurationMs, 95), p99 = percentile(DurationMs, 99), failures = countif(Success == false) by bin(TimeGenerated, 10s)
| order by TimeGenerated asc
```

Result:

| TimeGenerated (UTC) | InstanceCount | ReqCount | P50 (ms) | P95 (ms) | P99 (ms)  | Failures |
| ------------------- | ------------- | -------- | -------- | -------- | --------- | -------- |
| 09:16:20            | 1             | 38       | 6.42     | 26.07    | 30.40     | 0        |
| 09:16:30            | 4             | 255      | 16.67    | 7,579.25 | 13,350.24 | 0        |
| 09:16:40            | 4             | 443      | 31.07    | 176.10   | 4,164.01  | 0        |
| 09:16:50            | 4             | 808      | 30.57    | 94.24    | 191.33    | 0        |
| 09:17:00            | 4             | 771      | 27.20    | 82.50    | 131.68    | 0        |
| 09:17:10            | 4             | 794      | 21.48    | 74.35    | 114.96    | 0        |
| 09:17:20            | 4             | 751      | 28.07    | 70.75    | 87.27     | 0        |
| 09:17:30            | 4             | 716      | 25.97    | 67.78    | 103.49    | 0        |
| 09:17:40            | 4             | 718      | 27.90    | 73.95    | 104.97    | 0        |
| 09:17:50            | 4             | 678      | 31.25    | 85.24    | 114.77    | 0        |

**Note**: unlike the baseline (which started with all 4 instances already warm from
the warmup calls), this run's first bin shows only 1 instance handling 38 requests
before scaling to 4 in the next bin - a slightly different warmup interaction, but
irrelevant to the change under test. The elevated-latency bins (09:16:30 and
09:16:40) coincide with new instances finishing cold start/specialization while
already receiving traffic - same pattern as baseline, just spread over two 10s bins
instead of one. After that everything settles to single/double-digit millisecond P50
and P95 in the 70-95ms range, comparable to baseline's 56-107ms range.

### HTTP burst - first-seen per instance (ramp-up speed)

Query:

```kql
AppRequests
| where TimeGenerated between (datetime(2026-09-24T09:16:26.1120737Z) .. datetime(2026-09-24T09:18:10.1997206Z))
| where AppRoleName == "Web API Starter Functions"
| summarize firstSeen = min(TimeGenerated) by AppRoleInstance
| order by firstSeen asc
```

Result: all 4 instances online by `09:16:31.851`, i.e. **~3.0s** after burst start
(`09:16:28.854`) - slower than baseline's 1.72s, but baseline's 4 instances were
already warm from the immediately-preceding warmup calls, so the two numbers aren't
strictly apples-to-apples. Either way, both are well within a few seconds and neither
shows any sign of instances failing to come online or timing out.

### Queue burst - instance ramp-up + drain, 10s bins

Query:

```kql
AppRequests
| where TimeGenerated > datetime(2026-09-24T09:18:12.506236Z)
| where AppRoleName == "Web API Starter Functions"
| where Name has "ExampleQueue" and Name !has "ExceptionHandler"
| summarize instanceCount = dcount(AppRoleInstance), invocationCount = count(), succeeded = countif(Success == true), failed = countif(Success == false), lastSeen = max(TimeGenerated) by bin(TimeGenerated, 10s)
| order by TimeGenerated asc
```

Result:

| TimeGenerated (UTC) | InstanceCount | InvocationCount | Succeeded | Failed | LastSeen (UTC) |
| ------------------- | ------------- | --------------- | --------- | ------ | -------------- |
| 09:18:10            | 1             | 174             | 174       | 0      | 09:18:19.868   |
| 09:18:20            | 3             | 326             | 326       | 0      | 09:18:24.607   |

All 500 messages processed successfully on first attempt, 0 failures. Drain time
(last invocation minus enqueue start): 09:18:24.607 minus 09:18:12.506 = **~12.1s**
for 500 messages, comparable to baseline's ~11.5s. Peak instance count reached was 3
this run vs 5 in baseline - worth flagging, but since drain time and success rate
were unaffected, this looks like normal scale-controller variance rather than a
regression tied to the content-share removal (a single run each side isn't enough to
rule that out definitively).

### Queue burst - processing latency percentiles

Query:

```kql
AppRequests
| where TimeGenerated > datetime(2026-09-24T09:18:12.506236Z)
| where AppRoleName == "Web API Starter Functions"
| where Name has "ExampleQueue" and Name !has "ExceptionHandler"
| summarize total = count(), p50 = percentile(DurationMs, 50), p95 = percentile(DurationMs, 95), p99 = percentile(DurationMs, 99), min(DurationMs), max(DurationMs)
```

Result:

| Total | P50 (ms) | P95 (ms) | P99 (ms) | Min (ms) | Max (ms) |
| ----- | -------- | -------- | -------- | -------- | -------- |
| 500   | 58.03    | 762.19   | 1,291.13 | 9.24     | 1,334.94 |

Higher than baseline's 32/379/599ms P50/P95/P99, but still all well under 1.5s and
all 500 succeeded - consistent with the lower peak instance count (3 vs 5) spreading
the same 500-message burst across fewer workers, so each instance processes more
messages before the queue drains. Worth re-running a few more times before treating
this as conclusive, but it's not a failure or timeout signal.

### Client-observed periodic latency spikes (re-check from baseline)

Baseline flagged a recurring cluster of ~15,500-15,900ms client-observed HTTP
requests (still 200 OK), attributed tentatively to the API container app's
`MaxReplicas: 2` cap rather than the Function App change. Re-checked against this
run's `http-burst-results.csv`:

| Run                      | Total HTTP requests | Requests > 10,000ms client-observed | Rate  |
| ------------------------ | ------------------- | ----------------------------------- | ----- |
| baseline-contentshare-v2 | 6,567               | 14                                  | 0.21% |
| after-managed-identity   | 5,973               | 29                                  | 0.49% |

The spikes still occur in the same 15,500-18,000ms range in both runs (same
signature), but at roughly double the rate in the after-run. Given the small
absolute counts (14 vs 29 out of several thousand requests) this could just be
run-to-run noise from the API container app's own scaling, but it's flagged here in
case it recurs in a repeat run - it doesn't map to a queue burst failure or Function
App scale-out issue in the KQL data above.

## After run, round 2 (managed identity)

A second run against the same `sb/function-connection-string` deployment, to check
whether round 1's slower ramp-up / lower peak instance count / higher queue latency
was consistent or just noise:

```powershell
pwsh -NoProfile -File ./Test-FunctionScaleOut.ps1 -Label after-managed-identity-round2 -Mode Both `
  -HttpConcurrency 50 -HttpDurationSeconds 90 -QueueMessageCount 500 -QueueConcurrency 50
```

Artifacts: [`20260924-145951-after-managed-identity-round2/`](./runs/20260924-145951-after-managed-identity-round2/)

### Summary

| Burst | Total                       | Failures                              | Window (UTC)                                                        |
| ----- | --------------------------- | ------------------------------------- | ------------------------------------------------------------------- |
| HTTP  | 2,311 requests              | 16 (client-side SSL handshake errors) | 09:32:13.591 -> 09:33:59.582 (~106s)                                |
| Queue | 500 enqueued, 500 processed | 0                                     | enqueue 09:34:01.202 -> processing drained by 09:34:12.274 (~11.1s) |

**Note on the 16 HTTP failures**: these were all client-side
`The SSL connection could not be established` errors (plus one warmup request that
hit a Cloudflare `524` timeout), not server-side 4xx/5xx responses - and the KQL
query below confirms **0 server-side failures** in `AppRequests` for this window.
Total HTTP volume was also much lower this round (2,311 vs ~6,000 in prior runs),
consistent with a client-side network hiccup (e.g. local machine/network/Cloudflare
edge) throttling the load generator itself rather than anything happening in the
Function App or Container App.

### HTTP burst - instance ramp-up + latency, 10s bins

Query (workspace `log-was-dev`):

```kql
AppRequests
| where TimeGenerated between (datetime(2026-09-24T09:32:13.5911395Z) .. datetime(2026-09-24T09:33:59.5824119Z))
| where AppRoleName == "Web API Starter Functions"
| summarize instanceCount = dcount(AppRoleInstance), reqCount = count(), p50 = percentile(DurationMs, 50), p95 = percentile(DurationMs, 95), p99 = percentile(DurationMs, 99), failures = countif(Success == false) by bin(TimeGenerated, 10s)
| order by TimeGenerated asc
```

Result:

| TimeGenerated (UTC) | InstanceCount | ReqCount | P50 (ms) | P95 (ms) | P99 (ms) | Failures |
| ------------------- | ------------- | -------- | -------- | -------- | -------- | -------- |
| 09:32:10            | 7             | 207      | 6.09     | 21.37    | 67.11    | 0        |
| 09:32:20            | 5             | 315      | 6.13     | 29.60    | 45.36    | 0        |
| 09:32:30            | 5             | 251      | 4.58     | 11.48    | 20.89    | 0        |
| 09:32:40            | 3             | 239      | 4.59     | 15.77    | 18.31    | 0        |
| 09:32:50            | 3             | 240      | 4.39     | 10.03    | 19.50    | 0        |
| 09:33:00            | 3             | 169      | 4.57     | 13.87    | 19.66    | 0        |
| 09:33:10            | 6             | 328      | 5.11     | 20.19    | 24.88    | 0        |
| 09:33:20            | 6             | 176      | 4.76     | 21.11    | 33.82    | 0        |
| 09:33:30            | 5             | 196      | 5.46     | 23.87    | 38.83    | 0        |
| 09:33:40            | 4             | 161      | 5.14     | 16.01    | 18.90    | 0        |
| 09:33:50            | 1             | 10       | 4.62     | 11.57    | 11.57    | 0        |

**Zero server-side failures** across the whole window, confirming the 16 client-side
SSL errors never reached the Function App. Instance count fluctuated between 1 and 7
across the run (vs a flat 4 in round 1) - a noticeably more dynamic scaling pattern,
likely because the lower/uneven client throughput (from the network hiccup) produced
a choppier load profile than round 1's steady 50-worker saturation. Latency is
markedly lower than both the baseline and round 1 (single-digit P50, mostly
sub-30ms P95) - consistent with fewer concurrent requests per instance at any given
moment.

### HTTP burst - first-seen per instance (ramp-up speed)

Query:

```kql
AppRequests
| where TimeGenerated between (datetime(2026-09-24T09:32:13.5911395Z) .. datetime(2026-09-24T09:33:59.5824119Z))
| where AppRoleName == "Web API Starter Functions"
| summarize firstSeen = min(TimeGenerated) by AppRoleInstance
| order by firstSeen asc
```

Result: 7 distinct instances handled traffic this run (vs 4 in both prior runs),
first 6 online within **~3.9s** of burst start (09:32:13.591 -> 09:32:17.529), the
7th shortly after. Comparable ramp-up speed to round 1's ~3.0s despite reaching more
instances overall.

### Queue burst - instance ramp-up + drain, 10s bins

Query:

```kql
AppRequests
| where TimeGenerated > datetime(2026-09-24T09:34:01.2022509Z)
| where AppRoleName == "Web API Starter Functions"
| where Name has "ExampleQueue" and Name !has "ExceptionHandler"
| summarize instanceCount = dcount(AppRoleInstance), invocationCount = count(), succeeded = countif(Success == true), failed = countif(Success == false), lastSeen = max(TimeGenerated) by bin(TimeGenerated, 10s)
| order by TimeGenerated asc
```

Result:

| TimeGenerated (UTC) | InstanceCount | InvocationCount | Succeeded | Failed | LastSeen (UTC) |
| ------------------- | ------------- | --------------- | --------- | ------ | -------------- |
| 09:34:00            | 1             | 360             | 360       | 0      | 09:34:09.956   |
| 09:34:10            | 2             | 140             | 140       | 0      | 09:34:12.274   |

All 500 messages processed successfully on first attempt again, 0 failures. Drain
time: 09:34:12.274 minus 09:34:01.202 = **~11.1s**, in line with baseline's 11.5s and
round 1's 12.1s. Peak instance count reached was only **2** this round (vs 5 in
baseline, 3 in round 1) - a consistent downward trend across the two after-runs,
though drain time hasn't moved with it, so the queue is draining just as fast with
fewer instances doing more work each.

### Queue burst - processing latency percentiles

Query:

```kql
AppRequests
| where TimeGenerated > datetime(2026-09-24T09:34:01.2022509Z)
| where AppRoleName == "Web API Starter Functions"
| where Name has "ExampleQueue" and Name !has "ExceptionHandler"
| summarize total = count(), p50 = percentile(DurationMs, 50), p95 = percentile(DurationMs, 95), p99 = percentile(DurationMs, 99), min(DurationMs), max(DurationMs)
```

Result:

| Total | P50 (ms) | P95 (ms) | P99 (ms) | Min (ms) | Max (ms) |
| ----- | -------- | -------- | -------- | -------- | -------- |
| 500   | 20.80    | 100.12   | 197.40   | 9.01     | 351.63   |

Lower than both baseline (32/379/599ms) and round 1 (58/762/1,291ms), despite having
the lowest peak instance count (2) of all three runs. This breaks the round-1
hypothesis that fewer instances -> higher per-message latency; it looks more like
normal run-to-run variance in the scale controller/queue-poll timing than something
tied to instance count specifically.

## Before/after comparison

| Signal                                   | Baseline (content-share) | After round 1 (managed identity) | After round 2 (managed identity)        | Notes                                                                                                                                                                                                   |
| ---------------------------------------- | ------------------------ | -------------------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| HTTP burst total / failures              | 6,567 / 0                | 5,973 / 0                        | 2,311 / 16 (client SSL, 0 server-side)  | Round 2's failures were a client-side network blip, not a server-side issue - confirmed 0 in `AppRequests`                                                                                              |
| HTTP time to all instances online        | ~1.72s                   | ~3.0s                            | ~3.9s                                   | Baseline was already warm from pre-burst warmup; not strictly comparable to either after-run                                                                                                            |
| HTTP peak instance count                 | 4                        | 4                                | 7                                       | Round 2 reached more instances, likely due to choppier load profile from the network blip                                                                                                               |
| HTTP steady-state P50 / P95              | ~21-38ms / ~56-107ms     | ~21-31ms / ~68-95ms              | ~4-6ms / ~10-30ms                       | Round 2 markedly lower - consistent with less load per instance at any moment                                                                                                                           |
| HTTP client-observed spikes (>10s)       | 14 / 6,567 (0.21%)       | 29 / 5,973 (0.49%)               | not compared (throughput too different) | Flagged in round 1, not re-checked in round 2 given the confounding network blip                                                                                                                        |
| Queue burst total / failures             | 500 / 0                  | 500 / 0                          | 500 / 0                                 | All three clean, 0 failures, first-attempt success                                                                                                                                                      |
| Queue peak instance count                | 5                        | 3                                | 2                                       | Trending down across after-runs, but hasn't affected drain time or success rate                                                                                                                         |
| Queue drain time                         | ~11.5s                   | ~12.1s                           | ~11.1s                                  | All three comparable                                                                                                                                                                                    |
| Queue processing latency P50 / P95 / P99 | 32 / 379 / 599ms         | 58 / 762 / 1,291ms               | 21 / 100 / 197ms                        | Round 2 is the lowest of all three despite the lowest instance count - breaks the round-1 hypothesis that fewer instances drives higher latency; looks like normal scale-controller/queue-poll variance |

**Overall**: across baseline and two after-runs, the Function App scales out and
drains the queue reliably with **zero server-side failures** in every run. Metrics
move around from run to run (peak instance count, ramp-up time, latency
percentiles) but don't show a consistent, directional regression tied to the
content-share removal - round 2 actually had the _lowest_ queue latency of all three
runs despite the lowest instance count, and the only HTTP failures seen (round 2)
were confirmed client-side network errors rather than anything server-side. The
data across two after-runs doesn't show a scale-out reliability problem from
removing the content-share.

## Next steps

1. Use this before/after comparison (baseline + two after-runs) to make the final
   Y1-vs-Flex call.
2. If more confidence is wanted, re-run the HTTP burst once more on a network
   connection known to be stable (round 2's client-side SSL errors made its HTTP
   throughput/spike comparison less clean than round 1's).
3. Only after testing/deployment is fully verified: fix the stale `baseUrl` in
   `tests/postman/api-dev.postman_environment.json` (intentionally left alone until now).
