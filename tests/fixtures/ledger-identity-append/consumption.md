---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: ledger-identity-append)

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

> Basis: estimated. This fixture records only Entry One's identity, as if the ledger had last been regenerated before Entry Two (a zero-cost append) was added to history/ -- the C2 guard must treat that as a plain append (recorded is a prefix of current) and pass, never as a stale-total problem, since Entry Two contributed no tokens.

## Cost Comparison (illustrative)

Fixture for the C2 history-identity guard's "plain append passes" case.
