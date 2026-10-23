# Evidence: Flex Consumption performance

Supports [ADR 0003](../../0003-move-function-apps-to-flex-consumption.md). Run against the `dev` environment of this repo (`func-clc-was-dev-internalapi`) on 2026-10-21.

## Scale-out burst at 512 MB

Same script and settings as the [Y1 runs in ADR 0002](../0002-y1-vs-flex-scale-out-tests/README.md) (`-HttpConcurrency 50 -HttpDurationSeconds 90 -QueueMessageCount 500 -QueueConcurrency 50`). Artifacts: [`runs/20261021-150302-flex-512mb/`](./runs/20261021-150302-flex-512mb/).

| Burst | Result | Instances |
| --- | --- | --- |
| HTTP, API to Easy Auth to Function | 6,092 Echo executions, 0 failures, p50 97 ms, p95 246 ms | 11 |
| Queue, identity-based trigger | 500 of 500 processed, 0 failures | 9 |

Each of the 23 instances that ran during the test started its host exactly once. An instance killed for running out of memory would have started again, so none were. The worker's App Insights `Private Bytes` counter read p50 410 MB, p95 476 MB, max 492 MB. On Linux that counter can include memory that is reserved but not resident, so treat it as an upper bound. It is still close to the 512 MB instance size, which is why the sizing below matters.

## Memory sizing

Flex bills per configured instance size (512, 2,048 or 4,096 MB). The platform adds 272 MB on top for system and host processes. Y1 has no size setting and gives each instance 1.5 GB.

Thirty days of Y1 `PrivateBytes` (hourly maximum, host plus worker) as measured on Windows:

| App | Average | p95 | Max |
| --- | --- | --- | --- |
| web-api-starter dev internalapi | 267 MB | 390 MB | 551 MB (during the ADR 0002 burst test) |
| DSG internalapi, all environments | 329 to 398 MB | 350 to 483 MB | 409 to 657 MB |
| DSG deploypbi, all environments | 291 to 466 MB | 309 to 638 MB | 398 to 1,057 MB |

Windows numbers overstate what the same code needs on Linux under a 512 MB limit, because .NET sizes its GC heap to the memory it can see. Even so:

- **This template's internalapi** ran the burst test at 512 MB with no restarts. 512 MB is the default.
- **DSG internalapi** sits near this template's profile. 512 MB is a reasonable start if it gets the same burst test before going to production.
- **DSG deploypbi** reached about 1 GB in prod-na, qa and dev on Y1. Start it at 2,048 MB.

`instanceMemoryMB` is a parameter of `internal-api.bicep`, so each app can be sized on its own.

## What remains uncertain

- 512 MB was tested with this template's light workload only. DSG's Power BI orchestrations allocate more and have not run on Flex.

<!-- markdownlint-disable-file MD013 -->
