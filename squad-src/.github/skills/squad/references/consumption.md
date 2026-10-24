---
name: squad-consumption
description: "Squad consumption ledger templates, the dispatch-size cost estimator, cost formula, and Cost Preflight; the per-model rate table, tier fallback, and calibration block live in consumption-rates-template.md."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-24"
---

# Squad Consumption Ledger

## consumption.md

Authoritative ledger of squad members, the models they consumed, their billed token
categories, and native AI credits. With `-SessionLog auto`,
`Measure-SquadLedger.ps1` joins each complete native usage record's event `agentId`
to `subagent.started`, follows `parentAgentId` so nested workers roll into their
owning top-level role, and writes one exact ledger. Coordinator and Squad Scribe
records share `orchestration`. The row sum must equal the complete deduplicated
session nano-AIU total; otherwise the helper keeps the history estimator as an
explicit fallback rather than claiming exact attribution.

The ledger is split into two narrower tables that both key on `Role` — one **Attribution** table (who ran, on what model) and one **Usage & Cost** table (what it cost) — instead of one 15-column table, because a table wide enough to need horizontal scrolling defeats the point of a ledger a consumer should be able to read at a glance.

Replace semantics govern the file, not the rows. In exact mode every rewrite is a
native snapshot through the recorded timestamp and SHA-256 identity digest; active
and completed top-level role runs present in that snapshot are included. The
`history/*.md` entries still supply the append-only proof-of-dispatch identities and
the fallback estimator. Exact mode is admitted only when every history-backed role
and orchestration row has native coverage. A rewrite that reflects only the current
turn, silently omits a history-backed role, or cannot reconcile to the native total
falls back rather than presenting a partial exact ledger.

````markdown
---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: <run-id>)

## Attribution

| Role          | Member | Agent          | Model   | Model Source | Priced As | Tier   |
| ------------- | ------ | -------------- | ------- | ------------ | --------- | ------ |
| <role>        |        | <agent>        | <model> | <source>     | <model>   | <tier> |
| orchestration |        | <coord+scribe> | <model> | <source>     | <model>   | mixed  |

## Usage & Cost

| Role          | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | --------- |
| <role>        | 0     | 0         | 0      | 0        | 0          | 0.0000           | 0.00         | estimated |
| orchestration | 0     | 0         | 0      | 0        | 0          | 0.0000           | 0.00         | estimated |
| **Total**     | **0** | **0**     | **0**  | **0**    | **0**      | **0.0000**       | **0.00**     |           |

### Derivation

```text
Squad Scribe.md — 0 block(s) — identities: (none)

<role>         turns 0        0 × 0.00 +      0 × 0.00 +      0 × 0.00 +     0 × 0.00 =        0 / 1e6 = 0.0000
orchestration  turns 0+0=0    0 × 0.00 +      0 × 0.00 +      0 × 0.00 +     0 × 0.00 =        0 / 1e6 = 0.0000
                                                                                       total = 0.0000
```

> This is the initialization and fallback shape. Exact mode replaces `Turns` with
> `Requests`, `Est. Cost` / `Est. Credits` with `Exact Cost` / `Exact Credits`, and
> every row's basis with `exact-native`. Its input column is uncached billed input;
> cache read and cache write remain separate, so the four token columns are
> disjoint and reproduce native token-detail charges. The exact Attribution table
> uses `host-reported` and `native credits`; fallback Attribution preserves the
> existing model-source ladder. 1 AI credit = 0.01 USD.
>
> The `<file>.md — <n> block(s) — identities: <hash>,<hash>,...` line uses the history file's basename, without a `history/` prefix. It is the ledger's own record of which `###` entries it has already folded in, one short deterministic hash per entry in file order. The initial Scribe-only seed records an empty prefix; the first ledger write replaces it with actual identities. A rewrite that finds this run's recorded identities are not an ordered prefix of the file's current identities — same count but different hashes, or fewer current entries than recorded — means an entry was overwritten, reordered, or removed since the last rewrite rather than only appended to, and `Measure-SquadLedger.ps1 -Check` (or render mode) refuses rather than silently accepting it. A pre-existing ledger with no recorded identities at all (an older-format entry) only warns when checked plainly; it never fails on that account alone. But the Scribe's own post-write self-check always runs `-Check` together with `-ExpectedHistoryCounts` (*scribe-procedure.md*'s Write-Completeness Self-Check Step 3), and in that combination a Derivation missing identities entirely, or missing them for only some of the touched files (a partial paste), FAILS instead of warning — that call always follows a fresh write, so a missing or partial paste there is this run's own defect, never a genuinely old ledger.

## Cost Comparison (illustrative)

This run consumed an estimated **$<squad-cost> (~<squad-credits> AI credits)** across <n> specialized agents, routing read-heavy roles to lightweight models and reserving high-output reasoning models only where needed. Reproducing the same outcome by manually prompting <baseline-model> across roughly <iterations> iterate-and-test turns, each priced through the same dispatch-size estimator, is estimated at **$<manual-cost> (~<manual-credits> AI credits)** — a saving of about **<savings-pct>%**.

<optional per-phase or per-dispatch breakdown, added below the comparison and never in place of it>

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
````

`Measure-SquadLedger.ps1 -Write` finalizes the Cost Comparison from the same basis
as the ledger. Exact mode compares the authoritative native total, including
orchestration, with the same exact role-request token categories repriced on one
baseline model with no coordinator or Scribe. That baseline is a calculated
counterfactual, not an observed alternate run; it deliberately adds no hypothetical
context growth, rework, or behavioral change. When exact attribution is unavailable,
the historical estimated comparison remains the fallback. Run `-Check` afterward;
never hand-edit derived comparison figures after a successful check.

## consumption-rates.md

Single maintainable rate table that isolates volatile per-model token pricing from agent logic, plus the dispatch-size estimator and the calibration factor. Uses replace semantics. The Scribe seeds it from the template in [consumption-rates-template.md](consumption-rates-template.md) — a **cold** file, read only on initialization or at a Step 7.1 reseed, never on an ordinary decision or history dispatch — when the file is missing **or when the existing file does not carry the required sections** (see the Scribe's Step 7 shape check: a per-model rate table with `Input`, `Cached`, `Cache write`, and `Output` columns, a tier-fallback table, a dispatch-size estimator, and a calibration block), so a hand-edited or drifted table can never silently degrade every estimate. Because only this file holds token rates, a price change updates one table and never touches an agent prompt. Coordinators' Cost Preflight prices from the squad root's own `consumption-rates.md`, never from the template file.

## Orchestration overhead

Record actual coordinator/Scribe usage as one `orchestration` row per run: coordinator usage at its own model, plus `Scribe state write` usage only when Scribe actually ran. Direct deterministic handoffs add no fictional Scribe dispatch/tokens. Preserve the historical `history/Squad Scribe.md` overhead artifact on both routes; ordinary arithmetic is script-derived, never hand-authored.

The row is an aggregate, not the storage. Each turn's orchestration figures are appended as a `#### Consumption — Orchestration` block to `history/Squad Scribe.md`, and the row is the sum of every such block recorded for the run. A figure that lives only in the turn's payload cannot be read back, so the row resets to the current turn on the next rewrite and the run under-reports its own overhead by every turn that came before.

## Cost formula

Cost is derived **once per ledger row**, never in a history block. Sum the role's blocks into the four token columns, then take the rates from the row `priced_as` names in `consumption-rates.md`:

```text
raw_cost_usd = ( input_tokens       × input_rate
               + cached_tokens      × cached_rate
               + cache_write_tokens × cache_write_rate
               + output_tokens      × output_rate ) / 1e6
est_cost_usd = raw_cost_usd × calibration_factor
est_credits  = est_cost_usd / 0.01
```

Duplicated rates and costs drift. `calibration_factor` is read from the squad root's own `consumption-rates.md` — its calibration block and reconciliation procedure are documented in the template at [consumption-rates-template.md](consumption-rates-template.md), read only on initialization or a Step 7.1 reseed.

## Cost Preflight

`cost-ceiling=$X` admits Copilot model spend, not Azure workload cost. Initialization is outside Cost Preflight: the confirmed bootstrap path seeds accounting files and records setup spend without a ceiling slot. After initialization, consumed-to-date spend comes from complete native host usage records, deduplicated by `sourceSessionId + usageId` and by `compactionAttemptId`; a lagging checkpoint never replaces that sum. Future usage cannot be exact, so every later round reserves only the actual next dispatch wave plus the current coordinator lookup.

Missing identities, non-complete credit status, malformed relevant events, an unavailable session log/usage output, or an unpriced selected model yields low-confidence `cannot-confirm`, never approvable. When the host supports `--max-ai-credits`, set it at session launch as defense in depth; a ceiling supplied after launch can only gate later dispatches cooperatively.

Capture the first round's run boundary with
`Get-SquadUsage.ps1 -RepoRoot <repo> -SessionLog auto`; pass its `totalNanoAiu` as
`baselineNanoAiu`. The decision records that native baseline, so later rounds can
recover it without trusting model memory.

Resolve the effective ceiling before building the manifest:

1. A supplied finite positive number sets or replaces the ceiling for the active run.
2. The literal `cost-ceiling=unset` explicitly removes the ceiling. Persist the exact `not-requested` object, preserving accumulated cost totals, and continue without cost-based admission.
3. When the argument is omitted, inherit the latest finite positive `ceilingUsd` only if its non-empty Cost Preflight `runId` matches the active run id. Omission never means removal.
4. When the active run id differs, or no prior positive ceiling exists, omission means no ceiling for the new run and persists `not-requested`.

Resolve the active run id before this decision from the run the coordinator is continuing or creating. A new autopilot topic, Watch event, or federation meta-run gets a new id; a later request that resumes that recorded run keeps its id. Never copy a ceiling across run ids.

An effectively unset ceiling records `not-requested` and preserves existing behavior. A configured ceiling must be a finite positive USD number. The configured decisions are `within-ceiling`, `over-ceiling`, `approved-over-ceiling`, and `cannot-confirm`. `within-ceiling` and `approved-over-ceiling` permit only the exact next-dispatch set recorded by their round; the latter is created only by the explicit approval transition below.

### Actual next-wave reservation

Build the reservation from the actual `New-SquadDispatchPlan.ps1` input:

1. Resolve dependencies and take only wave 1. Later waves are recalculated after the previous wave has returned and its usage record is complete.
2. Add one row for each wave-1 unit and one `Lookup / single-file read` row for the coordinator turn that is not yet present in host metering. Direct deterministic handoffs add no fictional Scribe reservation.
3. Assign the canonical dispatch class from the selected role's assignment class: research, planning, implementation, review/intake, council, bookkeeping, or coordinator.
4. Use the class row's exact `Internal turns`, `Base context`, `Growth/turn`, and `Output/turn` values unless a larger pre-dispatch bound is known.
5. Price the actual routed model returned in the same plan. Under `off`, use the selected agent pin or concrete session model. `auto`, unresolved identity, a missing rate, or an invalid rate table is low confidence and cannot admit work.

Every readable Cost Preflight record uses this table shape. `Projected Cost` is the actual next-wave point estimate before the policy reserve; row calculations retain full precision.

| Slot | Stage | Role | Count | Dispatch Class | Pricing Basis | Internal Turns | Base Context | Growth/Turn | Output/Turn | Projected Cost |
|------|-------|------|------:|----------------|---------------|---------------:|-------------:|------------:|------------:|---------------:|
| <id> | <stage> | <role> | <n> | <class> | <model or max-candidate set> | <turns> | <tokens> | <tokens> | <tokens> | <usd> |

### Calculation and confidence

Calculate reservations through the existing dispatch-size and cost formulas, then sum unrounded row values:

```text
exact_used_usd       = (complete_total_nano_aiu - run_baseline_nano_aiu) / 1e11
evaluated_spend_usd = exact_used_usd + pending_usd
remaining_usd       = max(0, ceiling_usd - evaluated_spend_usd)
projected_cost_usd  = sum(unrounded actual-next-wave row costs)
reserve_multiplier  = 3.0
admission_cost_usd  = projected_cost_usd * reserve_multiplier
```

The factor-of-three reserve matches the repository's material uncertainty band for estimated ledger figures. It is a policy reserve, not a statistical confidence interval. Round displayed and persisted totals to four decimal places only after all rows are summed; never sum rounded display values.

**Pending reservation.** `pending_usd` is the still-running or returned-but-not-yet-metered admitted work. Keep it until complete usage records for that unit appear, then drop the reservation because exact host spend has replaced it. Never add an already-metered reservation twice.

Cost Preflight confidence is `medium` only when all are true:

* The configured ceiling is finite and positive.
* The actual next wave and coordinator reservation are complete.
* Every candidate model is fixed before dispatch and has a current rate row.
* The rate table passes its shape check.
* Exact host metering is complete through the latest readable event.

Otherwise confidence is `low`. The preflight never reports `high`, because future token use remains estimated.

Apply the decision in this order:

1. With no ceiling, record `not-requested` and do not gate existing behavior.
2. With an invalid ceiling or low confidence, record `cannot-confirm` and fire the Risk Gate.
3. When exact consumed spend plus pending reservations is at or above the ceiling, record `over-ceiling` with no permitted set and stop. This terminal boundary cannot be approved.
4. With medium confidence and `admission_cost_usd > remaining_usd`, record `over-ceiling` with no permitted set. Present the ceiling, exact consumed spend, pending reservations, remaining amount, next-wave point estimate, conservative admission cost, and the one-dispatch-unit overshoot limitation, then ask the user to stop or proceed under the unchanged ceiling.
5. Otherwise record `within-ceiling` and permit only that round's named next-dispatch set.

When the user chooses proceed, preserve the `over-ceiling` record and append a new round with a new round id. Copy its run id, ceiling, evaluated spend, exact next-wave rows, pricing inputs, costs, confidence, and basis; add `Approved From` and `Approval Ref` to the readable record; set its decision to `approved-over-ceiling`; and permit one sequential dispatch unit. Record that unit even when its final exact usage reaches or crosses the ceiling. Do not launch a parallel set from an approved-over-ceiling round.

The approval remains valid for later rounds only while the run id and ceiling are unchanged, confidence remains medium, and the next sequential unit is unchanged from the approved input. A changed ceiling, expanded or repriced unit, different model input, low confidence, or missing approval provenance requires a new gate; `cannot-confirm` is never approvable.

Immediately before each dispatch unit, refresh exact host usage and add pending reservations. When that evaluated spend is at or above `ceilingUsd`, append the terminal `over-ceiling` round, permit no slot, and stop. An in-flight unit cannot be interrupted, so its final exact usage may cross the ceiling; no later substantive child starts. If later routing changes the next wave, stop before dispatch and recalculate.

### Worked single-squad example

This example has 50 exact host credits already consumed (`0.5000 USD`) and an actual next wave containing one researcher plus the coordinator lookup:

```text
exact used                                  = 0.500000
coordinator lookup reservation             = 0.255280
researcher reservation                     = 1.553280
projected next wave                        = 1.808560
admission x3.0                             = 5.425680
```

With `ceilingUsd=10.0000`, `remainingUsd=9.5000`. The persisted point estimate is `1.8086`, admission cost is `5.4257`, and the decision is `within-ceiling` at medium confidence.

### Worked federation example

Federation Cost Preflight runs inside each selected member, where its session-log
scope and actual role wave are known. The federation root admits a member only after
that member's persisted preflight receipt; it never fabricates one aggregate exact
meter from unrelated member reservations.

## Comparison methodology

With complete native role attribution:

```text
exact_squad_usd = complete deduplicated session nano-AIU / 1e11
baseline_usd    = Σ each exact non-orchestration request's four disjoint token
                  categories priced on one baseline model, with that request's
                  long-context threshold applied
savings_usd     = baseline_usd - exact_squad_usd
savings_pct     = savings_usd / baseline_usd
```

The exact Squad side includes coordinator, Scribe, top-level roles, and nested
workers. The counterfactual excludes coordinator and Scribe and holds the exact
role-request traffic constant. It therefore measures model-routing savings on
identical traffic and is conservative about orchestration overhead, but it is not
an observed manual run. `-BaselineModel` overrides the default; otherwise the
helper selects the most expensive rate-resolved non-Hydra model used by a role.

Without complete native role attribution, the fallback remains:

```text
estimated_squad_cost = sum over history consumption blocks of estimated cost
manual_baseline      = explicitly supplied manual estimate
savings_pct          = 1 - (estimated_squad_cost / manual_baseline)
```

## Exact native role usage

When the coordinator has `pwsh` 7+, the trusted ledger invocation uses
`-SessionLog auto`. `Measure-SquadLedger.ps1` reads `events.jsonl` under
`$COPILOT_HOME/session-state/<session id>/` and:

* deduplicates complete `session.usage_record` identities by
  `sourceSessionId + usageId` and native compaction records by
  `compactionAttemptId`;
* reads event-level `agentId`, joins it to `subagent.started`, and follows
  `parentAgentId` so nested workers accrue to their top-level role;
* derives uncached input, cache read, cache write, and output from native
  `copilotUsage.tokenDetails`, requiring those charges to reproduce
  `totalNanoAiu`;
* combines coordinator and Squad Scribe usage as `orchestration`;
* requires every history-backed agent and orchestration row to have native
  coverage and the role-row nano-AIU sum to equal the session total; and
* records the native record count, through-timestamp, and SHA-256 identity digest
  in `### Derivation`.

There is no separate Observed Usage section. Exact native rows replace estimates in
the main tables and drive state totals, unit economics, and Cost Comparison.
Incomplete accounting, absent event-level identity, ambiguous roster mapping,
member-scoped coordinator attribution, missing history coverage, or a reconciliation
failure leaves the estimator visibly in place.

Every exact ledger is explicitly **as of** its recorded native timestamp. A model
request emitted after the helper reaches the log's then-current end appears on the
next rewrite; it is never backfilled as an estimate. This is also why Cost Preflight
keeps a reservation for the current coordinator lookup and in-flight work.

## Unit economics (value)

`Measure-SquadLedger.ps1 -Write` writes the `## Unit Economics (value)` section in every routing mode (replacing it on every rewrite before `## Cost Comparison`); it is never hand-authored, and `-Check` ignores it. It divides cost by value. A deliverable counts as accepted only when a review-class entry in the same `Turn` and `Workstream` covers it and its `Outcome` reads pass, pass-with-findings, or approved; fail, rejected, or blocked marks it rejected, and no covering review leaves it unreviewed. A review whose `Request` or `Outcome` names deliverables covers only those; a review that names none covers every deliverable of its turn and workstream, and the latest covering review wins. A deliverable is named by its full path, or by its file name only when no other deliverable of the same turn and workstream shares that file name: an ambiguous file name names neither deliverable (they stay unreviewed unless another review covers them), and the mention still keeps that review from covering every deliverable. A rework dispatch is a non-Scribe entry whose agent and deliverable path already appeared in an earlier entry; first-pass yield is the share of accepted deliverables with none. Exact mode reports measured credits per accepted deliverable and measured orchestration share. Exact rework-credit share remains unavailable until native run identities are bound one-to-one to individual history entries; fallback mode retains the estimated rework share.
