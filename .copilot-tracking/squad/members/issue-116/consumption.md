---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: issue-116)

## Attribution

| Role          | Member | Agent               | Model           | Model Source       | Priced As        | Tier    |
| ------------- | ------ | -------------------- | --------------- | ------------------- | ----------------- | ------- |
| developer     |        | Squad Implementor    | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | default |
| tester        |        | Squad Reviewer       | claude-sonnet-5 | session-inherited    | Claude Haiku 4.5  | fast    |
| orchestration |        | Coordinator + Scribe | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | mixed   |

## Usage & Cost

| Role          | Turns | In Tokens | Cached  | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------- | -------- | ---------- | ---------------- | ------------ | --------- |
| developer     | 16    | 95,000    | 340,000 | 58,000   | 11,000     | 0.5130            | 51.30        | estimated |
| tester        | 7     | 38,000    | 125,000 | 19,000   | 3,200      | 0.0903            | 9.03         | estimated |
| orchestration | 6     | 24,000    | 64,000  | 13,000   | 2,800      | 0.1213            | 12.13        | estimated |
| **Total**     | **29**| **157,000** | **529,000** | **90,000** | **17,000** | **0.7246**    | **72.46**   |           |

### Derivation

```text
developer      turns 16    95000 × 2.00 + 340000 × 0.20 +  58000 × 2.50 + 11000 × 10.00 = 513000 / 1e6 = 0.5130
tester         turns 7     38000 × 1.00 + 125000 × 0.10 +  19000 × 1.25 +  3200 ×  5.00 =  90250 / 1e6 = 0.0903
orchestration  turns 3+3=6 24000 × 2.00 +  64000 × 0.20 +  13000 × 2.50 +  2800 × 10.00 = 121300 / 1e6 = 0.1213
                                                                                          total = 0.7246
```

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API. `Model` is resolved per *Model Attribution* — `session-inherited` because no agent-pinned model or operator declaration overrode the session model. `Priced As` is the rate row used and differs from `Model` only for the `tester` row, which is priced at the `fast` tier's most expensive member per the tier-fallback rule. `Turns` for `developer` covers the hve-core repository clone at the target SHA, the five roster/agent-frontmatter/seed-template edits, the `apm.yml` regeneration, and the change-fragment authoring; `tester`'s covers the cast-delta re-run and the docs/README/CONTRIBUTING sweep; `orchestration`'s two blocks cover the sub-squad bootstrap and the final ledger/decisions write. The two tables share the same `Role` order so a row in one lines up with the same row in the other. Token rates and the dispatch-size estimator come from `consumption-rates.md` (copied verbatim from the `squad` skill template). Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$0.7246 (~72.46 AI credits)** across 2 specialized roles plus orchestration, verifying the retired `RPI Planner` agent against a live clone of hve-core at the exact target commit, repointing the roster row and agent-frontmatter lists across five files, regenerating `apm.yml`, and authoring a change fragment. Reproducing the same outcome by manually prompting a single high-capability model across roughly 8 iterate-and-test turns (repo cloning, frontmatter greps, roster/agent/seed-template edits, `apm.yml` regeneration, change-fragment authoring, and re-verification) at Claude Sonnet 5's default rate is estimated at **$2.00 (~200.00 AI credits)**, a reduction of about 64%.

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
