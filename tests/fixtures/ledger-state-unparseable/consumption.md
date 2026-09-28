---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: ledger-state-divergence)

## Attribution

| Role       | Member | Agent            | Model             | Model Source      | Priced As         | Tier    |
| ---------- | ------ | ----------------- | ----------------- | ------------------ | ------------------ | ------- |
| researcher | Alpha  | Squad Researcher  | Claude Sonnet 4.6 | session-inherited  | Claude Sonnet 4.6  | default |

## Usage & Cost

| Role       | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ---------- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | --------- |
| researcher | 1     | 100,000   | 0      | 0        | 0          | 0.3000           | 30.00        | estimated |
| **Total**  | **1** | **100,000** | **0** | **0** | **0**      | **0.3000**        | **30.00**    |           |

### Derivation

```text
Squad Researcher.md — 1 block(s) — identities: 3cc1ee8c
researcher     turns 1     100000 × 3.00 = 300000.0 / 1e6 = 0.3000
                                                              total = 0.3000
```

> Basis: estimated. consumption.md itself is fully correct and self-consistent; only state.json's currentRun deliberately diverges from it, to exercise the C3 ledger<->state.json divergence check in isolation from any consumption.md-shape or C2 identity concern.

## Cost Comparison (illustrative)

Fixture for the C3 ledger<->state.json currentRun divergence check's "fails, naming both values and the delta" case.
