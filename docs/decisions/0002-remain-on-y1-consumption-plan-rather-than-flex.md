# Remain on the Y1 Consumption plan for Function Apps rather than migrating to Flex Consumption

- Status: accepted
- Deciders: Sumedh Bhat
- Date: 2026-09-21

Technical Story: Migrate Function App host/deployment storage from connection strings (shared keys) to managed identity.

> **Where this decision belongs.** `web-api-starter` is the **template/starter** application for `data-services-gateway` (DSG/AIG). Infrastructure changes are prototyped and validated **here first**, then flow down into DSG. The substantive decision — including the full **measured, per-environment cost analysis** across all 20 DSG production Function Apps — is recorded in the DSG repo at `docs/decisions/0004-remain-on-y1-consumption-plan-rather-than-flex.md`. This ADR is the template-side counterpart: it captures the same decision so that anyone starting from `web-api-starter` inherits the rationale and the same Y1-plus-managed-identity pattern. Where numbers matter, defer to the DSG ADR.

## Context and Problem Statement

We are moving the template's Function Apps off connection-string (shared-key) access to the host storage account and onto **managed identity** (`allowSharedKeyAccess = false`, `AzureWebJobsStorage` via identity, package run from a private blob using `WEBSITE_RUN_FROM_PACKAGE` + `WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID`).

While making this change, an obvious question is whether the template should _also_ move from the **Y1 Consumption** plan to the newer **Flex Consumption** plan, which Microsoft now positions as the recommended serverless plan and which is "keyless-first" by design (blob-based deployment, managed identity throughout, no Azure Files content-share dependency).

### Why this question arises now: the managed-identity → Azure Files → scale-out chain

This question is a **direct consequence** of the managed-identity work, and the reasoning was surfaced by researching how Windows Consumption scales:

1. **We are removing shared keys.** The whole point of the change is `allowSharedKeyAccess = false` on the host storage account — no account keys, identity only.
2. **Azure Files cannot use managed identity for the Functions content share.** The `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` / Azure Files content share that Windows Consumption normally mounts **requires a storage account key**. Once we go keyless, we can no longer use it, so we must run the app **without an Azure Files content share** (package served from a private blob via `WEBSITE_RUN_FROM_PACKAGE`).
3. **Windows Consumption's dynamic scale-out is optimised around that Azure Files content share.**[^scaleout] Microsoft explicitly documents that when you run **without** Azure Files, _“scaling could be limited”_ on Consumption plans running on Windows.

So the trade-off is specifically this: **going keyless (managed identity) forces us off Azure Files, and being off Azure Files is what limits Windows Consumption scale-out.** Flex Consumption does not have this tension — it is keyless-first and has no Azure Files content-share dependency — so its scale-out is unaffected. That is precisely why the scale-out limitation (not cost) is the thing that would eventually push a real product onto Flex.

Should the template stay on Y1 Consumption, or adopt Flex Consumption as part of the managed-identity work?

## Decision Drivers

- **Security goal** — remove shared keys / secrets from the host storage configuration (the driver for the whole change).
- **Template fidelity** — the starter should demonstrate the pattern DSG actually ships, so downstream products inherit a sound default.
- **Cost** — Function Apps built from this template are expected to be low-volume; running cost should stay near-zero.
- **Migration effort and risk** — how much rework, and how reversible.
- **Operating-system / runtime constraints** — the apps are Windows, .NET isolated.
- **Scale and cold-start characteristics** — what the workload actually needs.

## Considered Options

- **Option 1 — Stay on Y1 Consumption, add managed identity, drop the Azure Files content share** (run from a private package blob).
- **Option 2 — Adopt Flex Consumption for the Function Apps.**
- **Option 3 — Adopt Elastic Premium (EP1).**

## Decision Outcome

Chosen option: **Option 1 — stay on Y1 Consumption with managed identity.**

Y1 fully satisfies the keyless/managed-identity security goal, keeps the template's run cost effectively **$0** at the low load these apps carry, and requires **no** operating-system change or app re-creation. Flex Consumption's benefits (VNet integration, faster/larger scale-out, always-ready cold-start mitigation) are not needed at template scale, and Flex is **materially more expensive per unit of work** while also forcing a Linux migration and a from-scratch app re-create. The DSG ADR quantifies this against real production load: the same measured workload on Flex costs roughly **12× more on 512 MB** and **46× more on 2 GB**, for zero functional benefit at current scale.

> **The primary trigger for moving to Flex is scale-out.** The single most important reason a product built on this template would leave Y1 Consumption is **if and when scaling out its Function Apps becomes a problem.** This limitation is a **direct side effect of the managed-identity migration**: going keyless forces the apps off the Azure Files content share, and Windows Consumption's dynamic scale-out is optimised around that share — so running without it is what constrains scale-out (_“scaling could be limited”_, per Microsoft). **When that reduced scale-out actually throttles throughput in production, that is the point to move to Flex Consumption — not before.** Cost is not the deciding factor. The migration is gated on **scaling headroom**, not dollars.

### Positive Consequences

- Meets the security objective (no shared keys on host storage) without a plan migration.
- No Linux migration, no app re-creation, no deployment-pipeline rewrite beyond the managed-identity package upload being introduced.
- Stays within Consumption free grants → negligible run cost.
- Reversible: the managed-identity + run-from-package changes are independent of the hosting plan.
- Gives downstream products (DSG and any other consumer of this template) a proven, secure default.

### Negative Consequences

- We accept the documented Y1 tradeoff of running **without an Azure Files content share** — a direct consequence of going keyless, since the content share requires a storage account key that `allowSharedKeyAccess = false` removes. Because Windows Consumption's dynamic scale-out is optimised around that share, dynamic scale-out “could be limited” (Microsoft's wording), portal code editing is disabled, and log streaming falls back to Application Insights. Acceptable for the template and for low-volume apps built from it — and this limited scale-out is exactly the condition that would later trigger a move to Flex (see “When to revisit”).
- We forgo Flex-only features (VNet integration, 1,000-instance scale-out, always-ready instances). None are required at template scale.
- We remain on a Windows Consumption plan whose feature set is frozen (no new features); Flex is where Microsoft invests going forward.

## Pros and Cons of the Options

### Option 1 — Stay on Y1 Consumption + managed identity

- Good, because it meets the keyless security goal with no plan migration.
- Good, because it stays within free grants (~$0/month) at current load.
- Good, because no Windows→Linux move and no app re-creation.
- Good, because it is reversible and decoupled from the hosting plan.
- Good, because it gives the template a secure, low-cost default that DSG and other consumers inherit.
- Bad, because dropping the Azure Files content share can limit dynamic scale-out on Windows Consumption (acceptable at template/low-volume scale).
- Bad, because Windows Consumption is feature-frozen.

### Option 2 — Adopt Flex Consumption

- Good, because it is keyless-first by design and the strategic long-term plan.
- Good, because it adds VNet integration, faster/larger scale-out (1,000 vs 200), and always-ready cold-start mitigation.
- Bad, because it is **Linux-only** — the Windows apps must be re-platformed.
- Bad, because **in-place migration is not supported**: a new app must be created and code redeployed; only one app per Flex plan.
- Bad, because it is **materially more expensive per unit of work** (higher rates, smaller free grants, instance-size-based GB-s billing, 1 s minimum execution) — see the measured factors in the DSG ADR.
- Bad, because the added capabilities are not needed at template scale.

### Option 3 — Adopt Elastic Premium (EP1)

- Good, because it removes cold starts and adds VNet integration.
- Bad, because it carries an **always-on fixed cost** (an EP1 instance runs ~$150+/month even idle) — unjustifiable for near-zero traffic.
- Bad, because it is the most expensive option by far for this workload.

## When to revisit

**The decisive trigger is scale-out.** A product built on this template moves from Y1 Consumption to Flex Consumption **when — and only when — scaling out its instances becomes a problem.** Recall _why_: the managed-identity migration removes shared-key access, which forces the apps off the Azure Files content share, and Windows Consumption's dynamic scale-out is optimised around that share — so scale-out is the capability the keyless move actually degrades. Concretely, act when any of the following is observed in production:

- The apps hit the **Windows Consumption scale-out ceiling** (200 instances) and requests are being queued or throttled at peak.
- Throughput is being limited by running **without an Azure Files content share** — i.e. dynamic scale-out is demonstrably constrained under load.
- Sustained execution volume grows beyond what Y1 can burst to.

Until an actual scale-out limitation is observed, stay on Y1 — cost is not a reason to move. Secondary reasons that could _also_ justify revisiting (but are not the primary driver): a need for **VNet integration**, **cold-start latency** becoming user-facing, or Microsoft announcing retirement of the Windows Consumption plan.

## Links

- DSG decision with full measured cost analysis: `data-services-gateway` → `docs/decisions/0004-remain-on-y1-consumption-plan-rather-than-flex.md`
- Storage considerations for Azure Functions — "Create an app without Azure Files": <https://learn.microsoft.com/en-us/azure/azure-functions/storage-considerations>
- Azure Functions Flex Consumption plan (instance sizes, billing, Linux-only, no in-place migration): <https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan>
- Azure Functions pricing: <https://azure.microsoft.com/en-us/pricing/details/functions/>

[^scaleout]: The precise internal mechanism is **not published by Microsoft**. What Microsoft documents is the observable behaviour — that running a Windows Consumption app _without_ an Azure Files content share means _“scaling could be limited”_. The statement that dynamic scale-out is “optimised around” the content share is our **interpretation** of that guidance (the share backs the app's content/deployment state that the scale controller relies on when adding instances), not a documented Microsoft internal. Treat it as a well-supported inference, not an official mechanism, and rely on the quoted “scaling could be limited” wording as the authoritative claim.

<!-- markdownlint-disable-file MD013 -->
