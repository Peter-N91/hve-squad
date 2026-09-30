---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: issue-129)

## Attribution

| Role          | Member | Agent               | Model           | Model Source       | Priced As        | Tier    |
| ------------- | ------ | -------------------- | --------------- | ------------------- | ----------------- | ------- |
| developer     |        | Squad Implementor    | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | default |
| tester        |        | Squad Reviewer       | claude-sonnet-5 | session-inherited    | Claude Haiku 4.5  | fast    |
| orchestration |        | Coordinator + Scribe | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | mixed   |

## Usage & Cost

| Role          | Turns | In Tokens | Cached  | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------- | -------- | ---------- | ---------------- | ------------ | --------- |
| developer     | 14    | 82,000    | 296,000 | 50,000   | 9,200      | 0.4402            | 44.02        | estimated |
| tester        | 9     | 46,000    | 158,000 | 24,000   | 4,100      | 0.1123            | 11.23        | estimated |
| orchestration | 6     | 22,000    | 60,000  | 12,000   | 2,600      | 0.1120            | 11.20        | estimated |
| **Total**     | **29**| **150,000** | **514,000** | **86,000** | **15,900** | **0.6645**    | **66.45**   |           |

### Derivation

```text
developer      turns 14    82000 × 2.00 + 296000 × 0.20 +  50000 × 2.50 +  9200 × 10.00 = 440200 / 1e6 = 0.4402
tester         turns 9     46000 × 1.00 + 158000 × 0.10 +  24000 × 1.25 +  4100 ×  5.00 = 112300 / 1e6 = 0.1123
orchestration  turns 3+3=6 22000 × 2.00 +  60000 × 0.20 +  12000 × 2.50 +  2600 × 10.00 = 112000 / 1e6 = 0.1120
                                                                                          total = 0.6645
```

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API. `Model` is resolved per *Model Attribution* — `session-inherited` because no agent-pinned model or operator declaration overrode the session model. `Priced As` is the rate row used and differs from `Model` only for the `tester` row, which is priced at the `fast` tier's most expensive member per the tier-fallback rule. `Turns` for `developer` covers the hve-core repository clone at the target SHA, the roster-row rewording, the `apm.yml` regeneration and diff cross-check, and the change-fragment authoring; `tester`'s covers the before/after cast-delta runs, the `agents:` frontmatter dispatchability audit against the cloned tree, the docs/README/CONTRIBUTING sweep, and the Manifest.Tests.ps1 run; `orchestration`'s two blocks cover the sub-squad bootstrap and the final ledger/decisions write. The two tables share the same `Role` order so a row in one lines up with the same row in the other. Token rates and the dispatch-size estimator come from `consumption-rates.md` (copied verbatim from the `squad` skill template). Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$0.6645 (~66.45 AI credits)** across 2 specialized roles plus orchestration, cross-checking the retired `graph-research` prompt against a live clone of hve-core at the exact target commit, rewording one roster row, regenerating `apm.yml`, and authoring a change fragment. Reproducing the same outcome by manually prompting a single high-capability model across roughly 7 iterate-and-test turns (repo cloning, roster-doc edits, `apm.yml` regeneration, change-fragment authoring, and re-verification) at Claude Sonnet 5's default rate is estimated at **$1.80 (~180.00 AI credits)**, a reduction of about 63%.

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
