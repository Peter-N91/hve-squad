---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: issue-104)

## Attribution

| Role          | Member | Agent               | Model           | Model Source       | Priced As        | Tier    |
| ------------- | ------ | -------------------- | --------------- | ------------------- | ----------------- | ------- |
| developer     |        | Squad Implementor    | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | default |
| tester        |        | Squad Reviewer       | claude-sonnet-5 | session-inherited    | Claude Haiku 4.5  | fast    |
| orchestration |        | Coordinator + Scribe | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | mixed   |

## Usage & Cost

| Role          | Turns | In Tokens | Cached  | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------- | -------- | ---------- | ---------------- | ------------ | --------- |
| developer     | 18    | 150,000   | 500,000 | 80,000   | 16,000     | 0.7600            | 76.00        | estimated |
| tester        | 8     | 55,000    | 190,000 | 30,000   | 5,000      | 0.1365            | 13.65        | estimated |
| orchestration | 6     | 30,000    | 80,000  | 15,000   | 3,000      | 0.1435            | 14.35        | estimated |
| **Total**     | **32**| **235,000** | **770,000** | **125,000** | **24,000** | **1.0400**    | **104.00**   |           |

### Derivation

```text
developer      turns 18   150000 × 2.00 + 500000 × 0.20 +  80000 × 2.50 + 16000 × 10.00 = 760000 / 1e6 = 0.7600
tester         turns 8     55000 × 1.00 + 190000 × 0.10 +  30000 × 1.25 +  5000 ×  5.00 = 136500 / 1e6 = 0.1365
orchestration  turns 6     30000 × 2.00 +  80000 × 0.20 +  15000 × 2.50 +  3000 × 10.00 = 143500 / 1e6 = 0.1435
                                                                                          total = 1.0400
```

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API. `Model` is resolved per *Model Attribution* — `session-inherited` because no agent-pinned model or operator declaration overrode the session model. `Priced As` is the rate row used and differs from `Model` only for the `tester` row, which is priced at the `fast` tier's most expensive member per the tier-fallback rule. `Turns` is the estimated internal tool-loop turn count for each dispatch, including the hve-core repository clone, frontmatter greps, mechanical renames, `apm.yml` regeneration, and two cast-delta re-runs. The two tables share the same `Role` order so a row in one lines up with the same row in the other. Token rates and the dispatch-size estimator come from `consumption-rates.md` (copied verbatim from the `squad` skill template). Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$1.0400 (~104.00 AI credits)** across 2 specialized roles plus orchestration, verifying the renamed replacement skills and the fully-removed agents against a live clone of hve-core at the exact target commit, and mechanically repointing five skill ids plus two prose mentions across three files. Reproducing the same outcome by manually prompting a single high-capability model across roughly 9 iterate-and-test turns (repo cloning, frontmatter greps, mechanical renames, roster edits, apm.yml regeneration, and re-verification) at Claude Sonnet 5's default rate is estimated at **$2.25 (~225.00 AI credits)**, a reduction of about 54%.

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
