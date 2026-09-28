---
description: "Per-model token rates, dispatch-size estimator, and calibration factor for squad consumption estimates"
---

# Consumption Rates (verify against the current GitHub Copilot "Models and pricing" docs)

* Billing model: usage-based billing (UBB), token-metered, effective 2026-06-01.
* Observed-on: 2026-09-27. Source: <https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing>
* Credit conversion: 1 AI credit = $0.01 USD (fixed).
* All rates are USD per 1M tokens. Anthropic models bill a separate cache-write rate on top of cached input; models without one leave the column at 0.

## Per-model token rates in USD per 1M tokens (volatile, verify before commit)

| Model (as routed) | Tier     | Input | Cached | Cache write | Output | Notes                      |
| ------------------ | -------- | ----- | ------ | ----------- | ------ | -------------------------- |
| GPT-5.4 nano        | fast     | 0.20  | 0.02   | 0           | 1.25   | lightweight, read-heavy    |
| Claude Sonnet 4.6   | default  | 3.00  | 0.30   | 3.75        | 15.00  | versatile                  |
| Claude Opus 5       | extended | 5.00  | 0.50   | 6.25        | 25.00  | high-capability reasoning  |

## Tier fallback rates (used only when `basis: tier-default`)

| Tier     | Priced as         | Input | Cached | Cache write | Output |
| -------- | ----------------- | ----- | ------ | ----------- | ------ |
| fast     | Claude Haiku 4.5  | 1.00  | 0.10   | 1.25        | 5.00   |
| default  | Claude Sonnet 4.6 | 3.00  | 0.30   | 3.75        | 15.00  |
| extended | Claude Opus 5     | 5.00  | 0.50   | 6.25        | 25.00  |

## Dispatch-size estimator

| Dispatch class            | Internal turns | Base context | Growth/turn | Output/turn |
| -------------------------- | --------------- | ------------ | ----------- | ----------- |
| Lookup / single-file read   | 3                | 20,000       | 3,000       | 800         |
| Research / file survey      | 12               | 40,000       | 4,000       | 1,250       |
| Scribe state write          | 4                | 15,000       | 3,000       | 800         |

## Orchestration overhead

One coordinator turn per dispatch round at the coordinator's own model, plus one `Scribe state write` class dispatch per Scribe hand-off, recorded as a single `orchestration` row summed from `#### Consumption — Orchestration` blocks in `history/Squad Scribe.md`.

## Cost formula

```text
raw_cost_usd = ( input_tokens       × input_rate
               + cached_tokens      × cached_rate
               + cache_write_tokens × cache_write_rate
               + output_tokens      × output_rate ) / 1e6
est_cost_usd = raw_cost_usd × calibration_factor
est_credits  = est_cost_usd / 0.01
```

## Calibration

```yaml
calibration_factor: 1.00
last_reconciled: never
observations: 0
estimator_revision: 2
calibration_basis: "2026-09-27|2"
```

## Cost Preflight

Not exercised by this fixture; see `consumption.md` in `squad-src/.github/skills/squad/references/` for the full Cost Preflight schema and worked examples.
