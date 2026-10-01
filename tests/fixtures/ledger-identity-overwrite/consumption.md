---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: ledger-identity-overwrite)

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

> Basis: estimated. This fixture's recorded identity (`3cc1ee8c`, for "Entry One") no longer matches history/'s current single entry, whose heading text was overwritten to "Entry One (renamed)" -- same entry count, different identity at the same position. The C2 guard must fail this as an overwrite, never treat it as a pass merely because the count is unchanged.

## Cost Comparison (illustrative)

Fixture for the C2 history-identity guard's "same-count overwrite fails" case.
