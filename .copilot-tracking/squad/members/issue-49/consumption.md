---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: issue-49)

## Attribution

| Role          | Member | Agent               | Model           | Model Source       | Priced As | Tier    |
| ------------- | ------ | -------------------- | --------------- | ------------------- | --------- | ------- |
| developer     |        | Squad Implementor    | claude-sonnet-5 | session-inherited    | claude-sonnet-5 | default |
| tester        |        | Squad Reviewer       | claude-sonnet-5 | session-inherited    | Claude Haiku 4.5 | fast    |
| orchestration |        | Coordinator + Scribe | claude-sonnet-5 | session-inherited    | claude-sonnet-5 | mixed   |

## Usage & Cost

| Role          | Turns | In Tokens | Cached  | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------- | -------- | ---------- | ---------------- | ------------ | --------- |
| developer     | 8     | 100,000   | 400,000 | 60,000   | 12,000     | 0.5500           | 55.00        | estimated |
| tester        | 4     | 30,000    | 120,000 | 20,000   | 3,000      | 0.0820            | 8.20         | estimated |
| orchestration | 3     | 20,000    | 60,000  | 15,000   | 3,000      | 0.1195            | 11.95        | estimated |
| **Total**     | **15**| **150,000** | **580,000** | **95,000** | **18,000** | **$0.7515**    | **75.15**    |           |

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API. `Model` is resolved per *Model Attribution* — `session-inherited` because no agent-pinned model or operator declaration overrode the session model. `Priced As` is the rate row used and differs from `Model` only for the `tester` row, which is priced at the `fast` tier's most expensive member per the tier-fallback rule. `Turns` is the estimated internal tool-loop turn count for the dispatch. The two tables share the same `Role` order so a row in one lines up with the same row in the other. Token rates and the dispatch-size estimator come from `consumption-rates.md` (observed 2026-08-03). Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$0.7515 (~75.15 AI credits)** across 2 specialized roles plus orchestration, routing the read-heavy review to a lightweight-priced tier and reserving the reasoning-heavy documentation fix for the default tier. Reproducing the same outcome by manually prompting a single high-capability model across roughly 10 iterate-and-test turns is estimated at **$2.20 (~220.00 AI credits)**, a reduction of about 66%.

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
