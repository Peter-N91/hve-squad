---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: issue-109)

## Attribution

| Role          | Member | Agent               | Model           | Model Source       | Priced As        | Tier    |
| ------------- | ------ | -------------------- | --------------- | ------------------- | ----------------- | ------- |
| developer     |        | Squad Implementor    | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | default |
| tester        |        | Squad Reviewer       | claude-sonnet-5 | session-inherited    | Claude Haiku 4.5  | fast    |
| orchestration |        | Coordinator + Scribe | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | mixed   |

## Usage & Cost

| Role          | Turns | In Tokens | Cached  | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------- | -------- | ---------- | ---------------- | ------------ | --------- |
| developer     | 14    | 90,000    | 320,000 | 55,000   | 10,000     | 0.4815            | 48.15        | estimated |
| tester        | 6     | 35,000    | 120,000 | 18,000   | 3,000      | 0.0845            | 8.45         | estimated |
| orchestration | 5     | 22,000    | 60,000  | 12,000   | 2,500      | 0.1110            | 11.10        | estimated |
| **Total**     | **25**| **147,000** | **500,000** | **85,000** | **15,500** | **0.6770**    | **67.70**   |           |

### Derivation

```text
developer      turns 14    90000 × 2.00 + 320000 × 0.20 +  55000 × 2.50 + 10000 × 10.00 = 481500 / 1e6 = 0.4815
tester         turns 6     35000 × 1.00 + 120000 × 0.10 +  18000 × 1.25 +  3000 ×  5.00 =  84500 / 1e6 = 0.0845
orchestration  turns 5     22000 × 2.00 +  60000 × 0.20 +  12000 × 2.50 +  2500 × 10.00 = 111000 / 1e6 = 0.1110
                                                                                          total = 0.6770
```

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API. `Model` is resolved per *Model Attribution* — `session-inherited` because no agent-pinned model or operator declaration overrode the session model. `Priced As` is the rate row used and differs from `Model` only for the `tester` row, which is priced at the `fast` tier's most expensive member per the tier-fallback rule. `Turns` is the estimated internal tool-loop turn count for each dispatch, including the hve-core repository clone at the target SHA, frontmatter and prose greps, the two roster/agent-frontmatter edits, `apm.yml` regeneration, the change fragment, and two cast-delta re-runs. The two tables share the same `Role` order so a row in one lines up with the same row in the other. Token rates and the dispatch-size estimator come from `consumption-rates.md` (copied verbatim from the `squad` skill template). Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$0.6770 (~67.70 AI credits)** across 2 specialized roles plus orchestration, verifying the single retired agent reference and its replacement surface against a live clone of hve-core at the exact target commit, and repointing the roster row and two agent-frontmatter lists across three files. Reproducing the same outcome by manually prompting a single high-capability model across roughly 7 iterate-and-test turns (repo cloning, frontmatter greps, roster/agent edits, `apm.yml` regeneration, and re-verification) at Claude Sonnet 5's default rate is estimated at **$1.75 (~175.00 AI credits)**, a reduction of about 61%.

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
