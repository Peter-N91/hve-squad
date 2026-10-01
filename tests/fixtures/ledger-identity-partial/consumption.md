---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: ledger-identity-partial)

## Attribution

| Role       | Member | Agent            | Model             | Model Source      | Priced As         | Tier    |
| ---------- | ------ | ----------------- | ----------------- | ------------------ | ------------------ | ------- |
| researcher | Alpha  | Squad Researcher  | Claude Sonnet 4.6 | session-inherited  | Claude Sonnet 4.6  | default |
| developer  | Beta   | Squad Developer   | Claude Sonnet 4.6 | session-inherited  | Claude Sonnet 4.6  | default |

## Usage & Cost

| Role       | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ---------- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | --------- |
| researcher | 1     | 100,000   | 0      | 0        | 0          | 0.3000           | 30.00        | estimated |
| developer  | 1     | 100,000   | 0      | 0        | 0          | 0.3000           | 30.00        | estimated |
| **Total**  | **2** | **200,000** | **0** | **0** | **0**      | **0.6000**        | **60.00**    |           |

### Derivation

```text
Squad Researcher.md — 1 block(s) — identities: 9d425e68
researcher     turns 1     100000 × 3.00 = 300000.0 / 1e6 = 0.3000
developer      turns 1     100000 × 3.00 = 300000.0 / 1e6 = 0.3000
                                                              total = 0.6000
```

> Basis: estimated. This fixture's Derivation records `Squad Researcher.md`'s identities correctly (matching history/'s current single entry exactly) but omits `Squad Developer.md`'s enumeration line entirely -- a partial paste of the helper's own printed Derivation, as if only some of its per-file lines were copied into the file. A plain `-Check` (no `-ExpectedHistoryCounts`) only warns on the file missing from the recorded identities, same as it would for a legacy line; `-Check -ExpectedHistoryCounts` (the Scribe's post-write self-check) must instead FAIL, naming `Squad Developer.md`, because that call always follows a fresh write and a partial paste there is this run's own defect.

## Cost Comparison (illustrative)

Fixture for the F3 review-fix: the C2 history-identity guard's post-write mode must fail when the Derivation records identities for only some of the touched history files.
