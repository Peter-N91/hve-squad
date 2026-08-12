---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: issue-62)

## Attribution

| Role          | Member | Agent               | Model           | Model Source       | Priced As | Tier    |
| ------------- | ------ | -------------------- | --------------- | -------------------- | --------- | ------- |
| developer     |        | Squad Implementor    | claude-sonnet-5 | session-inherited    | claude-sonnet-5 | default |
| tester        |        | Squad Reviewer       | claude-sonnet-5 | session-inherited    | Claude Haiku 4.5 | fast    |
| orchestration |        | Coordinator + Scribe | claude-sonnet-5 | session-inherited    | claude-sonnet-5 | mixed   |

## Usage & Cost

| Role          | Turns | In Tokens | Cached  | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------- | -------- | ---------- | ---------------- | ------------ | --------- |
| developer     | 34    | 260,000   | 950,000 | 140,000  | 28,000     | 1.3400            | 134.00       | estimated |
| tester        | 9     | 70,000    | 260,000 | 40,000   | 7,000      | 0.1810            | 18.10        | estimated |
| orchestration | 5     | 40,000    | 100,000 | 20,000   | 4,000      | 0.1500            | 15.00        | estimated |
| **Total**     | **48**| **370,000** | **1,310,000** | **200,000** | **39,000** | **$1.6710**    | **167.10**   |           |

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API. `Model` is resolved per *Model Attribution* — `session-inherited` because no agent-pinned model or operator declaration overrode the session model. `Priced As` is the rate row used and differs from `Model` only for the `tester` row, which is priced at the `fast` tier's most expensive member per the tier-fallback rule. `Turns` is the estimated internal tool-loop turn count for the dispatch, including the two rounds of hve-core repository verification (agent-frontmatter inspection and the cast-delta re-run). The two tables share the same `Role` order so a row in one lines up with the same row in the other. Token rates and the dispatch-size estimator come from `consumption-rates.md` (observed 2026-08-03). Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$1.6710 (~167.10 AI credits)** across 2 specialized roles plus orchestration, verifying the replacement cast against a live clone of hve-core at the exact target commit rather than trusting the attached delta report's prose. Reproducing the same outcome by manually prompting a single high-capability model across roughly 15 iterate-and-test turns (repo cloning, frontmatter greps, roster edits, apm.yml regeneration, and re-verification) is estimated at **$3.75 (~375.00 AI credits)**, a reduction of about 55%.

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
