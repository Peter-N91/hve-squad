---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: ledger-identity-full-postwrite)

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

> Basis: estimated. This fixture's Derivation records `Squad Researcher.md`'s identities completely -- one recorded identity for the one entry history/ currently holds, an exact match rather than a shorter prefix. `-Check -ExpectedHistoryCounts` (the Scribe's post-write self-check) must PASS cleanly here, with no C2 warning and no failure, proving post-write mode does not punish a correctly-pasted, fully up-to-date Derivation.

## Cost Comparison (illustrative)

Fixture for the F3 review-fix: the C2 history-identity guard's post-write mode passes cleanly when every touched history file's identities are fully and correctly recorded.
