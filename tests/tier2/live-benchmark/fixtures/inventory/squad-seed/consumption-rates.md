---
description: "Per-model token rates, dispatch-size estimator, and calibration factor for squad consumption estimates"
---

# Consumption Rates (verify against the current GitHub Copilot "Models and pricing" docs)

* Billing model: usage-based billing (UBB), token-metered, effective 2026-06-01.
* Observed-on: 2026-09-30.
* Credit conversion: 1 AI credit = $0.01 USD (fixed).

## Tier fallback rates (used when `basis: tier-default`)

| Tier     | Priced as         | Input | Cached | Cache write | Output |
| -------- | ----------------- | ----- | ------ | ----------- | ------ |
| fast     | Claude Haiku 4.5  | 1.00  | 0.10   | 1.25        | 5.00   |
| default  | Claude Sonnet 4.6 | 3.00  | 0.30   | 3.75        | 15.00  |
| extended | Claude Opus 5     | 5.00  | 0.50   | 6.25        | 25.00  |

## Dispatch-size estimator

| Dispatch class            | Internal turns | Base context | Growth/turn | Output/turn |
| ------------------------- | -------------- | ------------ | ----------- | ----------- |
| Lookup / single-file read | 3              | 20,000       | 3,000       | 800         |
| Research / file survey    | 12             | 40,000       | 4,000       | 1,250       |
| Plan / synthesis          | 15             | 60,000       | 4,000       | 2,000       |
| Implement / edit loop     | 35             | 60,000       | 6,000       | 2,000       |
| Review / verification     | 18             | 50,000       | 4,000       | 1,500       |
| Scribe state write        | 4              | 15,000       | 3,000       | 800         |

## Calibration

```yaml
calibration_factor: 1.00
last_reconciled: never
observations: 0
estimator_revision: 2
calibration_basis: "2026-09-30|2"
```
