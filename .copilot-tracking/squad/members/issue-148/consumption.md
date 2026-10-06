---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: issue-148)

## Attribution

| Role          | Member | Agent               | Model           | Model Source       | Priced As        | Tier    |
| ------------- | ------ | -------------------- | --------------- | ------------------- | ----------------- | ------- |
| developer     |        | Squad Implementor    | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | default |
| tester        |        | Squad Reviewer       | claude-sonnet-5 | session-inherited    | Claude Haiku 4.5  | fast    |
| orchestration |        | Coordinator + Scribe | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | mixed   |

## Usage & Cost

| Role          | Turns | In Tokens | Cached  | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------- | -------- | ---------- | ---------------- | ------------ | --------- |
| developer     | 16    | 95,000    | 340,000 | 58,000   | 10,500     | 0.5080            | 50.80        | estimated |
| tester        | 10    | 50,000    | 170,000 | 26,000   | 4,500      | 0.1220            | 12.20        | estimated |
| orchestration | 6     | 22,100    | 60,000  | 12,000   | 2,550      | 0.1117            | 11.17        | estimated |
| **Total**     | **32**| **167,100** | **570,000** | **96,000** | **17,550** | **0.7417**    | **74.17**   |           |

### Derivation

```text
developer      turns 16    95000 × 2.00 + 340000 × 0.20 +  58000 × 2.50 + 10500 × 10.00 = 508000 / 1e6 = 0.5080
tester         turns 10    50000 × 1.00 + 170000 × 0.10 +  26000 × 1.25 +  4500 ×  5.00 = 122000 / 1e6 = 0.1220
orchestration  turns 3+3=6 22100 × 2.00 +  60000 × 0.20 +  12000 × 2.50 +  2550 × 10.00 = 111700 / 1e6 = 0.1117
                                                                                          total = 0.7417
```

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API. `Model` is resolved per *Model Attribution* — `session-inherited` because no agent-pinned model or operator declaration overrode the session model. `Priced As` is the rate row used and differs from `Model` only for the `tester` row, which is priced at the `fast` tier's most expensive member per the tier-fallback rule. `Turns` for `developer` covers reading the roster instructions' Dispatchability and Deliverable Roots sections, cloning hve-core at the target SHA to confirm the three skills' removal and the `hve-builder` replacement, rewriting `squad-prompt-engineer.agent.md`'s description/purpose/steps/response format, rewording the two `roster-catalog.md` rows and the `squad-roster.instructions.md` sentence, running `Update-ApmDependencies.ps1`, and authoring the change fragment; `tester`'s covers the before/after cast-delta runs, the live hve-core clone frontmatter audit across both coordinator agents' 37 hve-core-sourced entries, the docs/README/CONTRIBUTING sweep, and the `Manifest.Tests.ps1` run; `orchestration`'s two blocks cover the sub-squad bootstrap and the final ledger/decisions write. The two tables share the same `Role` order so a row in one lines up with the same row in the other. Token rates and the dispatch-size estimator come from `consumption-rates.md` (copied verbatim from the `squad` skill template). Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$0.7417 (~74.17 AI credits)** across 2 specialized roles plus orchestration, cross-checking the three retired prompt-engineering compatibility skills against a live clone of hve-core at the exact target commit, confirming all 37 hve-core-sourced agent names in both coordinator charters' `agents:` lists still resolve and remain dispatchable, rewriting one squad-owned charter and two reference files, regenerating `apm.yml`, and authoring a change fragment. Reproducing the same outcome by manually prompting a single high-capability model across roughly 8 iterate-and-test turns (repo cloning, charter and roster-doc edits, `apm.yml` regeneration, change-fragment authoring, and re-verification) at Claude Sonnet 5's default rate is estimated at **$2.05 (~205.00 AI credits)**, a reduction of about 64%.

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
