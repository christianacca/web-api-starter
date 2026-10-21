# Evidence: why Y1 deployments failed, and Flex Consumption deployment reliability

Supports [ADR 0003](../../0003-move-function-apps-to-flex-consumption.md). All tests ran against the `dev` environment of this repo (`func-clc-was-dev-internalapi`, `rg-dev-was-eastus2`) on 2026-10-21. Nothing was run against `data-services-gateway` (DSG). DSG GitHub Actions logs and Azure Monitor metrics were only read.

## 1. What the failures looked like in DSG

DSG run [37497895120](https://github.com/MRI-Software/data-services-gateway/actions/runs/37497895120) ("Application Deploy Production Release", 2026-10-06) needed 11 attempts. Every one of the 10 failed attempts failed in the step that ran the custom `azure-function-packages` action, with the same error:

```text
ERROR: Bad Request({"Code":"BadRequest","Message":"Encountered an error (ServiceUnavailable) from host runtime.", ...})
```

The failing call was always `POST .../syncfunctiontriggers`, made 4 to 50 seconds after `az functionapp restart` returned. Both DSG Function Apps (`internalapi` and `deploypbi`) failed this way, across `demo`, `demo-na`, `demo-apac`, `prod-na` and `prod-apac`. DSG later wrapped the sync call in a retry loop (20 attempts, 15 seconds apart), which hides the symptom.

## 2. Reproducing it in this repo (Y1, before the move)

[`Invoke-SyncTriggerRepro.ps1`](./Invoke-SyncTriggerRepro.ps1) replays what the custom action did after uploading the package: `az functionapp restart`, then `syncfunctiontriggers` straight away, retrying every 5 seconds until it succeeds.

| Scenario | What was happening in the app | First sync call failed | Time until sync succeeded |
| --- | --- | --- | --- |
| Idle | nothing | 1 of 3 | 8 to 23 s |
| Warm | 20 queue messages sent 45 s earlier | 1 of 5 | 7 to 25 s |
| Busy | continuous queue load during the restart | 0 of 5 | 7 to 20 s |
| Control, no restart | continuous queue load | 0 of 5 | 3 to 14 s |

Every failure returned the exact DSG error. Host logs for the failure at 07:22 UTC show why:

```text
07:22:27  az functionapp restart issued (returned after ~4 s)
07:22:31  syncfunctiontriggers -> ServiceUnavailable from host runtime
07:22:33  Job host stopped
07:22:51  Host started
```

`az functionapp restart` returns before the Functions host has restarted. The sync call then reaches the app while the old host is stopping or the new one hasn't started, and the host answers 503. Whether the call loses the race depends on timing, which is why reruns eventually passed. Apps with longer start-up (more functions, Durable Functions, cold prod instances) have a wider window, which fits DSG failing more often than this template.

In-flight executions did not cause the failures. The busy runs had no failures, and nothing failed without a restart. The restart did have a separate cost: it stopped the Durable task hub with `IsGracefulStop: False`, so executions running at the time were cut off.

## 3. Flex Consumption with Azure/functions-action

After moving to Flex Consumption, the [app pipeline](https://github.com/christianacca/web-api-starter/actions/runs/39576871310) deployed with `Azure/functions-action@v1`. Its log:

```text
Detected function app sku: FlexConsumption
Will use Kudu https://<scmsite>/api/publish to deploy since Flex consumption plan is detected.
Package deployment using One Deploy initiated.
Successfully deployed web package to Function App.
```

The pipeline no longer calls restart or sync itself. One Deploy writes the package to the `app-package` container with the app's user-assigned identity, then the platform restarts the app and syncs triggers. All 12 functions were registered afterwards.

### Repeated deployments

[`Invoke-FlexDeployRepro.ps1`](./Invoke-FlexDeployRepro.ps1) deployed the pipeline-built package 10 times using `az functionapp deployment source config-zip`, which calls the same One Deploy endpoint as the action. Results: [`runs/flex-deploy-results.csv`](./runs/flex-deploy-results.csv).

| Scenario | Deployments | Succeeded | All 12 functions registered afterwards |
| --- | --- | --- | --- |
| Idle | 5 | 4 | 5 of 5 |
| Busy (continuous queue load) | 5 | 5 | 5 of 5 |

The one failure (Idle 4) was `RemoteDisconnected` while uploading the 17 MB package from the test machine, after 529 seconds. That machine was dropping large transfers in both directions the same afternoon (GitHub artifact and blob downloads stalled at about 85%). The activity log has no post-publish call for that attempt, so the upload never reached the platform. It is not the Y1 failure mode.

During the 5 busy deployments the test sent 5,090 queue messages. Application Insights recorded 5,090 `ExampleQueue` executions, all successful, all on their first delivery (`DequeueCount: 1`). There were no exceptions, and both `default-queue` and `default-queue-poison` were empty afterwards. These executions take milliseconds. Long-running executions would still be cut off by the `Recreate` update strategy (see the ADR).

### Scale-out burst at 512 MB

Same script and settings as the [Y1 runs in ADR 0002](../0002-y1-vs-flex-scale-out-tests/README.md) (`-HttpConcurrency 50 -HttpDurationSeconds 90 -QueueMessageCount 500 -QueueConcurrency 50`). Artifacts: [`runs/20261021-150302-flex-512mb/`](./runs/20261021-150302-flex-512mb/).

| Burst | Result | Instances |
| --- | --- | --- |
| HTTP, API to Easy Auth to Function | 6,092 Echo executions, 0 failures, p50 97 ms, p95 246 ms | 11 |
| Queue, identity-based trigger | 500 of 500 processed, 0 failures | 9 |

Each of the 23 instances that ran during the test started its host exactly once. An instance killed for running out of memory would have started again, so none were. The worker's App Insights `Private Bytes` counter read p50 410 MB, p95 476 MB, max 492 MB. On Linux that counter can include memory that is reserved but not resident, so treat it as an upper bound. It is still closer to the 512 MB instance size than I'd like, which is why section 4 matters.

## 4. Memory sizing

Flex bills per configured instance size (512, 2,048 or 4,096 MB). The platform adds 272 MB on top for system and host processes. Y1 has no size setting and gives each instance 1.5 GB.

Thirty days of Y1 `PrivateBytes` (hourly maximum, host plus worker) as measured on Windows:

| App | Average | p95 | Max |
| --- | --- | --- | --- |
| web-api-starter dev internalapi | 267 MB | 390 MB | 551 MB (during the ADR 0002 burst test) |
| DSG internalapi, all environments | 329 to 398 MB | 350 to 483 MB | 409 to 657 MB |
| DSG deploypbi, all environments | 291 to 466 MB | 309 to 638 MB | 398 to 1,057 MB |

Windows numbers overstate what the same code needs on Linux under a 512 MB limit, because .NET sizes its GC heap to the memory it can see. Even so:

- **This template's internalapi** ran the burst test and 10 deployments at 512 MB with no restarts. 512 MB is the default.
- **DSG internalapi** sits near this template's profile. 512 MB is a reasonable start if it gets the same burst test before going to production.
- **DSG deploypbi** reached about 1 GB in prod-na, qa and dev on Y1. Start it at 2,048 MB.

`instanceMemoryMB` is a parameter of `internal-api.bicep`, so each app can be sized on its own.

## What remains uncertain

- The Y1 repro was 2 failures in 13 restarts. That is enough to show the race but not to estimate DSG's failure rate.
- Flex rolling updates (`RollingUpdate`) were not tested because the template uses the default, `Recreate`.
- 512 MB was tested with this template's light workload only. DSG's Power BI orchestrations allocate more and have not run on Flex.

<!-- markdownlint-disable-file MD013 -->
