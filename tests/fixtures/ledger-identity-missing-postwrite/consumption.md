---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: ledger-identity-missing-postwrite)

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

> Basis: estimated. This is the pre-C2, older-format Derivation shape: no per-file `— identities:` enumeration line at all. A plain `-Check` (no `-ExpectedHistoryCounts`) only warns ("an older-format ledger") on a ledger like this, exactly like `ledger-identity-legacy`. This fixture's own purpose is the opposite case: `-Check -ExpectedHistoryCounts` (the Scribe's post-write self-check) must instead FAIL here, because that call always follows a fresh write and a Derivation missing every identity line is this run's own bad paste, never a genuinely old ledger.

## Cost Comparison (illustrative)

Fixture for the F3 review-fix: the C2 history-identity guard's post-write ("`-Check` + `-ExpectedHistoryCounts`") mode must fail on a fully-missing-identities Derivation, never only warn.
