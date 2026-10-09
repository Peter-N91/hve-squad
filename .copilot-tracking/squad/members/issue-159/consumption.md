---
description: "Member, model, and credit ledger for sub-squad issue-159"
---

# Consumption Ledger (issue-159)

Run: 1

## Usage & Cost

| Role         | Turns | Input     | Cached    | Cache Write | Output | Cost (USD) | Credits |
| ------------ | ----- | --------- | --------- | ----------- | ------ | ---------- | ------- |
| orchestration | 45   | 1,485,000 | 5,940,000 | 275,000     | 72,000 | 5.5655     | 556.55  |
| **Total**    | **45**| **1,485,000** | **5,940,000** | **275,000** | **72,000** | **5.5655** | **556.55** |

### Derivation

```text
orchestration  turns 45   1485000 × 2.00 + 5940000 × 0.20 + 275000 × 2.50 + 72000 × 10.00 = 5565500 / 1e6 = 5.5655
                                                                                            total = 5.5655
```

Priced from `consumption-rates.md`'s `Claude Sonnet 5` row (`default` tier): Input 2.00, Cached 0.20, Cache write 2.50, Output 10.00 USD per 1M tokens. `calibration_factor` is `1.00` (uncalibrated; `consumption-rates.md`'s calibration block has `observations: 0`).

Only one row exists because no role beyond the coordinator's own orchestration was dispatched this run — see the honesty note in `history/Squad Scribe.md` and *Blocking findings* in `decisions.md`.

## Cost Comparison

* **This run's cost**: $5.5655 (556.55 credits), one orchestration turn.
* **Manual baseline**: the brief's nine numbered steps (read roster conventions, repoint five at-risk references across the identified files, update two coordinator agent frontmatters, update seed templates/routing, run the apm dependency script, author a change fragment, update docs, re-run the delta script) would, performed by a human-directed agent, plausibly take 4 iterations of focused review-and-edit at the `default` tier's dispatch-size estimator "Implement / edit loop" floor (35 internal turns, 60,000 base context, 6,000 growth/turn, 2,000 output/turn) each, priced at the `Claude Sonnet 5` rate: 4 × $4.5352 ≈ $18.1408.
* **Saving**: approximately 69% versus the manual baseline, reflecting that this run resolved the full adaptation in a single coordinated pass rather than four iterative review-and-edit cycles.
