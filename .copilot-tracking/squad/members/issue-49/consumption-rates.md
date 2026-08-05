---
description: "Per-model token rates, dispatch-size estimator, and calibration factor for squad consumption estimates"
---

# Consumption Rates (verify against the current GitHub Copilot "Models and pricing" docs)

* Billing model: usage-based billing (UBB), token-metered, effective 2026-06-01.
* Observed-on: 2026-08-03. Source: <https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing>
* Credit conversion: 1 AI credit = $0.01 USD (fixed).
* All rates are USD per 1M tokens. Anthropic models bill a separate cache-write rate on top of cached input; models without one leave the column at 0.

## Per-model token rates in USD per 1M tokens (volatile, verify before commit)

| Model (as routed) | Tier     | Input | Cached | Cache write | Output | Notes                      |
| ----------------- | -------- | ----- | ------ | ----------- | ------ | -------------------------- |
| GPT-5.4 nano       | fast     | 0.20  | 0.02   | 0           | 1.25   | lightweight, read-heavy    |
| GPT-5.4 mini       | fast     | 0.75  | 0.075  | 0           | 4.50   | lightweight                |
| Claude Haiku 4.5   | fast     | 1.00  | 0.10   | 1.25        | 5.00   | lightweight reasoning      |
| Claude Sonnet 4.6  | default  | 3.00  | 0.30   | 3.75        | 15.00  | versatile                  |
| Claude Sonnet 5    | default  | 2.00  | 0.20   | 2.50        | 10.00  | versatile (promo pricing)  |
| GPT-5.4            | default  | 2.50  | 0.25   | 0           | 15.00  | versatile                  |
| Gemini 3.1 Pro      | default  | 2.00  | 0.20   | 0           | 12.00  | versatile                  |
| Claude Opus 4.8     | extended | 5.00  | 0.50   | 6.25        | 25.00  | high-capability reasoning  |
| Claude Opus 5       | extended | 5.00  | 0.50   | 6.25        | 25.00  | high-capability reasoning  |
| GPT-5.5             | extended | 5.00  | 0.50   | 0           | 30.00  | high-capability reasoning  |
| (additional)        |          |       |        |             |        | update when GitHub changes |

## Tier fallback rates (used only when `basis: tier-default`)

A tier is a routing preference, not a price. When the actual model is unknown, price the tier at its **most expensive member** rather than a blend: the observed failure mode of this ledger is undercounting, so the fallback is deliberately conservative-high and every row it produces is flagged `basis: tier-default`.

The `Priced as` column below names a model for **pricing only**. Never write it into a consumption block's `model` field.

| Tier     | Priced as         | Input | Cached | Cache write | Output |
| -------- | ----------------- | ----- | ------ | ----------- | ------ |
| fast     | Claude Haiku 4.5  | 1.00  | 0.10   | 1.25        | 5.00   |
| default  | Claude Sonnet 4.6 | 3.00  | 0.30   | 3.75        | 15.00  |
| extended | Claude Opus 5     | 5.00  | 0.50   | 6.25        | 25.00  |

## Dispatch-size estimator

Estimated per the methodology in `.github/skills/squad/SKILL.md`: `internal_turns × average_context` for gross input, split 80/20 cached/fresh, with a separate cache-write component for Anthropic models.

## Calibration

* `calibration_factor`: 1.00 (uncalibrated — no reconciled runs yet)
* `observations`: 0
* `last_reconciled`: n/a
