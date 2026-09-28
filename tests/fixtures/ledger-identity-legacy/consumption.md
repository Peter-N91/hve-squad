---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: ledger-identity-legacy)

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
researcher     turns 1     100000 × 3.00 = 300000.0 / 1e6 = 0.3000
                                                              total = 0.3000
```

> Basis: estimated. This is the pre-C2, older-format Derivation shape: no per-file `— identities:` enumeration line at all. The C2 guard must only warn ("an older-format ledger") on a ledger like this, never fail it, so existing checked-in ledgers keep working until their next rewrite records identities for the first time.

## Cost Comparison (illustrative)

Fixture for the C2 history-identity guard's "legacy ledger without identities warns" case.
