---
name: squad-consumption
description: "Squad consumption ledger templates and the dispatch-size cost estimator, formula, and calibration guidance."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-08-14"
---

# Squad Consumption Ledger

## consumption.md

Scribe-aggregated ledger of squad members, the model each consumed, and estimated AI-credit cost; this is the common "members and credits" readme. Uses replace semantics: the Scribe rewrites it each turn, mirrors roster order, and recomputes the run total and the comparison line from `consumption-rates.md`. Every figure is an estimate, because no per-dispatch token telemetry exists (the runtime exposes only the per-user aggregate `ai_credits_used`); token counts are estimated and cost and credits are derived, never billed.

The ledger is split into two narrower tables that both key on `Role` — one **Attribution** table (who ran, on what model) and one **Usage & Cost** table (what it cost) — instead of one 15-column table, because a table wide enough to need horizontal scrolling defeats the point of a ledger a consumer should be able to read at a glance.

Replace semantics govern the file, not the rows. Every rewrite is derived from the full set of per-dispatch consumption blocks recorded in `history/*.md` for the run, summed per role, so a role dispatched early keeps its row for the rest of the run and a role dispatched repeatedly holds one summed row. A rewrite that reflects only the current turn's dispatches produces a ledger that adds up correctly and is still wrong.

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
<role>         turns 0        0 × 0.00 +      0 × 0.00 +      0 × 0.00 +     0 × 0.00 =        0 / 1e6 = 0.0000
orchestration  turns 0+0=0    0 × 0.00 +      0 × 0.00 +      0 × 0.00 +     0 × 0.00 =        0 / 1e6 = 0.0000
                                                                                       total = 0.0000
```

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API. `Model` is resolved per *Model Attribution* in `.github/instructions/squad/squad-state.instructions.md` and is never invented — `unknown` where it could not be resolved. `Model Source` is `cli-pinned`, `operator-declared`, `dispatch-reported`, `agent-pinned`, `session-inherited`, or `unresolved`; an `agent-pinned` row legitimately differs from the session model. `Priced As` is the rate row used and differs from `Model` only on a fallback. `Turns` is the estimated internal tool-loop turn count, because a dispatch is many model calls and not one; it accumulates across a role's blocks exactly as the token columns do, so a role dispatched twice at `15` and `4` carries `19`. The two tables share the same `Role` order so a row in one lines up with the same row in the other. Token rates and the dispatch-size estimator come from `consumption-rates.md` (observed <date>). Calibration factor <factor> (<observations> reconciled run(s)). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$<squad-cost> (~<squad-credits> AI credits)** across <n> specialized agents, routing read-heavy roles to lightweight models and reserving high-output reasoning models only where needed. Reproducing the same outcome by manually prompting <baseline-model> across roughly <iterations> iterate-and-test turns, each priced through the same dispatch-size estimator, is estimated at **$<manual-cost> (~<manual-credits> AI credits)** — a saving of about **<savings-pct>%**.

<optional per-phase or per-dispatch breakdown, added below the comparison and never in place of it>

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
````

## consumption-rates.md

Single maintainable rate table that isolates volatile per-model token pricing from agent logic, plus the dispatch-size estimator and the calibration factor. Uses replace semantics. The Scribe seeds it from this template when the file is missing **or when the existing file does not carry the required sections** (see the Scribe's Step 7 shape check), so a hand-edited or drifted table can never silently degrade every estimate. Because only this file holds token rates, a price change updates one table and never touches an agent prompt.

````markdown
---
description: "Per-model token rates, dispatch-size estimator, and calibration factor for squad consumption estimates"
---

# Consumption Rates (verify against the current GitHub Copilot "Models and pricing" docs)

* Billing model: usage-based billing (UBB), token-metered, effective 2026-06-01.
* Observed-on: <YYYY-MM-DD>. Source: <https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing>
* Credit conversion: 1 AI credit = $0.01 USD (fixed).
* All rates are USD per 1M tokens. Anthropic models bill a separate cache-write rate on top of cached input; models without one leave the column at 0.

## Per-model token rates in USD per 1M tokens (volatile, verify before commit)

| Model (as routed) | Tier     | Input | Cached | Cache write | Output | Notes                      |
| ----------------- | -------- | ----- | ------ | ----------- | ------ | -------------------------- |
| GPT-5.4 nano      | fast     | 0.20  | 0.02   | 0           | 1.25   | lightweight, read-heavy    |
| GPT-5.4 mini      | fast     | 0.75  | 0.075  | 0           | 4.50   | lightweight                |
| Claude Haiku 4.5  | fast     | 1.00  | 0.10   | 1.25        | 5.00   | lightweight reasoning      |
| Claude Sonnet 4.6 | default  | 3.00  | 0.30   | 3.75        | 15.00  | versatile                  |
| Claude Sonnet 5   | default  | 2.00  | 0.20   | 2.50        | 10.00  | versatile (promo pricing)  |
| GPT-5.4           | default  | 2.50  | 0.25   | 0           | 15.00  | versatile                  |
| Gemini 3.1 Pro    | default  | 2.00  | 0.20   | 0           | 12.00  | versatile                  |
| Claude Opus 4.8   | extended | 5.00  | 0.50   | 6.25        | 25.00  | high-capability reasoning  |
| Claude Opus 5     | extended | 5.00  | 0.50   | 6.25        | 25.00  | high-capability reasoning  |
| GPT-5.5           | extended | 5.00  | 0.50   | 0           | 30.00  | high-capability reasoning  |
| (additional)      |          |       |        |             |        | update when GitHub changes |

## Tier fallback rates (used only when `basis: tier-default`)

A tier is a routing preference, not a price. When the actual model is unknown, price the tier at its **most expensive member** rather than a blend: the observed failure mode of this ledger is undercounting, so the fallback is deliberately conservative-high and every row it produces is flagged `basis: tier-default`.

The `Priced as` column below names a model for **pricing only**. Never write it into a consumption block's `model` field — that field records what actually ran and is resolved per *Model Attribution* in `.github/instructions/squad/squad-state.instructions.md`, or left as the literal `unknown`. Copying a `Priced as` name into `model` is exactly the fabrication that makes a ledger report spend against a model the operator never chose.

| Tier     | Priced as         | Input | Cached | Cache write | Output |
| -------- | ----------------- | ----- | ------ | ----------- | ------ |
| fast     | Claude Haiku 4.5  | 1.00  | 0.10   | 1.25        | 5.00   |
| default  | Claude Sonnet 4.6 | 3.00  | 0.30   | 3.75        | 15.00  |
| extended | Claude Opus 5     | 5.00  | 0.50   | 6.25        | 25.00  |

## Dispatch-size estimator

A dispatch is **not one model call**. A dispatched subagent runs an internal tool loop, and every internal turn resends the accumulated context. Input therefore scales with `internal_turns × average_context`, not with a single prompt-and-reply pair. Pricing a dispatch as one call is what makes a ledger read an order of magnitude below the bill.

```text
tokens(bytes)      = bytes / 4
base_context       = agent prompt + auto-applied instructions + loaded skill content
average_context    = base_context + growth_per_turn × (internal_turns - 1) / 2
gross_input        = internal_turns × average_context
```

Split `gross_input` across the billed rates. Turn 1 is fully uncached; on turns 2..n the carried-forward prefix is a cached read and only the new tool result is fresh input:

```text
cached_tokens      = gross_input × 0.80
input_tokens       = gross_input × 0.20
cache_write_tokens = base_context + growth_per_turn × (internal_turns - 1)   (Anthropic models only; 0 otherwise)
output_tokens      = internal_turns × output_per_turn
```

Estimate `internal_turns` and `base_context` from what the dispatch actually reported. These class rows are **floors, not fallbacks** — start here and raise, never start below:

| Dispatch class            | Internal turns | Base context | Growth/turn | Output/turn |
| ------------------------- | -------------- | ------------ | ----------- | ----------- |
| Lookup / single-file read | 3              | 20,000       | 3,000       | 800         |
| Research / file survey    | 12             | 40,000       | 4,000       | 1,250       |
| Plan / synthesis          | 15             | 60,000       | 4,000       | 2,000       |
| Implement / edit loop     | 35             | 60,000       | 6,000       | 2,000       |
| Review / verification     | 18             | 50,000       | 4,000       | 1,500       |
| Council member opinion    | 10             | 50,000       | 4,000       | 1,500       |
| Scribe state write        | 4              | 15,000       | 3,000       | 800         |

Observable proxies that raise a floor whenever available: the number of files the agent reported reading and their byte size, the byte size of artifacts it wrote, the count of tool calls it reported, and the length of the findings it returned.

**Validity check.** After estimating, confirm `gross_input / internal_turns >= base_context` for the class. A derived average context below the floor means the dispatch was sized from the summary the coordinator handed over rather than from the dispatch's own context. That summary is a report *about* the dispatch, not the context the dispatch ran on — an agent's prompt plus its auto-applied instructions already exceeds most floors before it reads a single file. When the check fails, raise the numbers and recompute rather than recording the smaller figure.

## Orchestration overhead

The coordinator's own turns and each Scribe write consume tokens too, and they are dispatches the ledger would otherwise never see. Record them as a single `orchestration` row per run: one coordinator turn per dispatch round at the coordinator's own model, plus one `Scribe state write` class dispatch per Scribe hand-off.

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

A rate is a property of the model, so it belongs to the one file that lists models. Copying it into every block restates the same fact once per dispatch and gives it that many chances to be restated wrong, and a cost stored beside its own inputs is a second copy of a number the inputs already determine.

## Calibration

```yaml
calibration_factor: 1.00
last_reconciled: never
observations: 0
```

The factor is the running mean of `observed_credits / estimated_credits` across reconciled runs, clamped to the range 0.25-10.0. To reconcile: read the per-user aggregate `ai_credits_used` from the Copilot usage-metrics REST API immediately before and after a run, take the delta as `observed_credits`, divide by the run's `est_credits` total, fold that ratio into the mean, and rewrite this block. Until `observations` is at least 1 the factor stays 1.00 and the ledger carries an "uncalibrated" note.

## Comparison methodology (token terms)

* `squad_cost = sum over dispatched roles of est_cost_usd`
* `manual_baseline = expected_iterations × baseline_model_cost_per_turn`, where a manual turn is itself priced through the dispatch-size estimator rather than as a single call
* `savings_pct = 1 - (squad_cost / manual_baseline)`

All values are labeled estimated, and token counts are estimated because no per-dispatch telemetry exists.
````
