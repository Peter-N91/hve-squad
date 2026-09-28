---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: rp-fixture-01)

## Attribution

| Role          | Member | Agent            | Model             | Model Source      | Priced As         | Tier    |
| ------------- | ------ | ----------------- | ----------------- | ------------------ | ------------------ | ------- |
| researcher    | Alpha  | Squad Researcher  | Claude Sonnet 4.6 | session-inherited  | Claude Sonnet 4.6  | default |
| orchestration |        | Squad Scribe      | Claude Haiku 4.5  | agent-pinned       | Claude Haiku 4.5   | fast    |

## Usage & Cost

| Role          | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | --------- |
| researcher    | 12    | 9,600     | 38,400 | 8,000    | 15,000     | 0.2953           | 29.53        | estimated |
| orchestration | 4     | 3,000     | 12,000 | 1,250    | 3,200      | 0.0218           | 2.18         | estimated |
| **Total**     | **16**| **12,600**| **50,400** | **9,250** | **18,200** | **0.8854**    | **88.54**    |           |

### Derivation

```text
researcher     turns 12    9600 × 3.00 + 38400 × 0.30 +  8000 × 3.75 + 15000 × 15.00 = 295320.0 / 1e6 = 0.2953
orchestration  turns 4     3000 × 1.00 + 12000 × 0.10 +  1250 × 1.25 +  3200 ×  5.00 =  21762.5 / 1e6 = 0.0218
                                                                                        total = 0.3171
```

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API. `Model` is resolved per *Model Attribution*. `Priced As` matches `Model` for both rows. Token rates and the dispatch-size estimator come from `consumption-rates.md`. Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$0.8854 (~88.54 AI credits)** across 1 specialized role plus orchestration, surveying the fixture-topic's existing conventions and recommending a minimal seed shape.

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
