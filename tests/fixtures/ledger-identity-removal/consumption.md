---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: ledger-identity-removal)

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
Squad Researcher.md — 2 block(s) — identities: 3cc1ee8c,69caf492
researcher     turns 1     100000 × 3.00 = 300000.0 / 1e6 = 0.3000
                                                              total = 0.3000
```

> Basis: estimated. This fixture records identities for two entries (Entry One and a zero-cost Entry Two), but history/'s current Squad Researcher.md now holds only Entry One -- an entry was removed, not merely left unappended-to. Because Entry Two was zero-cost, the Total row is unaffected by its removal, isolating the C2 guard's own removal-detection from the unrelated Total-row tolerance check. The C2 guard must fail this even though the remaining entry's own identity (`3cc1ee8c`) is still a prefix match by itself.

## Cost Comparison (illustrative)

Fixture for the C2 history-identity guard's "removal fails" case.
