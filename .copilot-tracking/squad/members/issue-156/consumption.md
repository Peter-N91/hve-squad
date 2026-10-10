---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: issue-156)

## Attribution

| Role          | Member | Agent               | Model           | Model Source       | Priced As        | Tier    |
| ------------- | ------ | -------------------- | --------------- | ------------------- | ----------------- | ------- |
| developer     |        | Squad Implementor    | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | default |
| tester        |        | Squad Reviewer       | claude-sonnet-5 | session-inherited    | Claude Haiku 4.5  | fast    |
| orchestration |        | Coordinator + Scribe | claude-sonnet-5 | session-inherited    | Claude Sonnet 5   | mixed   |

## Usage & Cost

| Role          | Turns | In Tokens | Cached  | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------- | -------- | ---------- | ---------------- | ------------ | --------- |
| developer     | 18    | 108,000   | 392,000 | 64,000   | 12,200     | 0.5764            | 57.64        | estimated |
| tester        | 9     | 46,000    | 158,000 | 24,000   | 4,100      | 0.1123            | 11.23        | estimated |
| orchestration | 6     | 20,500    | 55,000  | 11,000   | 2,350      | 0.1030            | 10.30        | estimated |
| **Total**     | **33**| **174,500** | **605,000** | **99,000** | **18,650** | **0.7917**    | **79.17**   |           |

### Derivation

```text
developer      turns 18   108000 × 2.00 + 392000 × 0.20 +  64000 × 2.50 + 12200 × 10.00 = 576400 / 1e6 = 0.5764
tester         turns 9     46000 × 1.00 + 158000 × 0.10 +  24000 × 1.25 +  4100 ×  5.00 = 112300 / 1e6 = 0.1123
orchestration  turns 3+3=6 20500 × 2.00 +  55000 × 0.20 +  11000 × 2.50 +  2350 × 10.00 = 103000 / 1e6 = 0.1030
                                                                                          total = 0.7917
```

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API. `Model` is resolved per *Model Attribution* — `session-inherited` because no agent-pinned model or operator declaration overrode the session model. `Priced As` is the rate row used and differs from `Model` only for the `tester` row, which is priced at the `fast` tier's most expensive member per the tier-fallback rule. `Turns` for `developer` covers reading the roster instructions' Dispatchability and Deliverable Roots sections, cloning hve-core at the target SHA to confirm the prompt-surface removal and the three skill replacements plus the two no-replacement removals, rewriting four squad-owned charters (`squad-azure-diagnose`, `squad-risk-manager`, `squad-data-scientist`, `squad-vulnerability-manager`), the `squad-roster.instructions.md` Dispatchability bullet and `SSSC Reviewer` table row, four `roster-catalog.md` rows, diagnosing and working around the cast-delta script's prompt-reference regex false positive, running `Update-ApmDependencies.ps1`, and authoring the change fragment; `tester`'s covers the dispatchability sweep, the before/after and old-pin/new-pin cast-delta re-runs, the `apm.yml`/`CHANGELOG.md` diff checks, the docs/README/CONTRIBUTING sweep, and the `Manifest.Tests.ps1`/`Packaging.Tests.ps1` runs; `orchestration`'s two blocks cover the sub-squad bootstrap and the final ledger/decisions write. The two tables share the same `Role` order so a row in one lines up with the same row in the other. Token rates and the dispatch-size estimator come from `consumption-rates.md` (copied verbatim from the `squad` skill template). Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$0.7917 (~79.17 AI credits)** across 2 specialized roles plus orchestration, cross-checking a hve-core-wide prompt-to-skill surface migration against a live clone of hve-core at the exact target commit, repointing four squad-owned charters and two reference files away from five retired prompts, diagnosing and working around a verification script's path-matching false positive, regenerating `apm.yml`, and authoring a change fragment. Reproducing the same outcome by manually prompting a single high-capability model across roughly 9 iterate-and-test turns (repo cloning, four charter rewrites, two reference-doc rewrites, `apm.yml` regeneration, change-fragment authoring, and re-verification against the script's quirks) at Claude Sonnet 5's default rate is estimated at **$2.31 (~231.00 AI credits)**, a reduction of about 66%.

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
