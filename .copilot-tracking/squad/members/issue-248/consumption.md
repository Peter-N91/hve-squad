---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: autopilot-run-42922858257)

## Attribution

| Role | Member | Agent | Model | Model Source | Priced As | Tier |
| ---- | ------ | ----- | ----- | ------------ | --------- | ---- |
| researcher |  | Squad Researcher | claude-sonnet-5.5 | agent-pinned | Claude Sonnet 5.5 | default |
| lead |  | Squad Lead | claude-sonnet-5.5 | agent-pinned | Claude Sonnet 5.5 | default |
| developer |  | Squad Implementor | claude-sonnet-5.5 | agent-pinned | Claude Sonnet 5.5 | default |
| tester |  | Squad Reviewer | claude-haiku-5.5 | agent-pinned | Claude Haiku 5.5 | fast |
| orchestration |  | Squad Scribe | unknown | unresolved | Claude Sonnet 4.6 | mixed |

## Usage & Cost

| Role | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis |
| ---- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | ----- |
| researcher | 12 | 148,800 | 595,200 | 84,000 | 15,000 | 0.7171 | 71.71 | estimated |
| lead | 15 | 264,000 | 1,056,000 | 116,000 | 30,000 | 1.2236 | 122.36 | estimated |
| developer | 105 | 3,402,000 | 13,608,000 | 792,000 | 210,000 | 12.2448 | 1,224.48 | estimated |
| tester | 54 | 907,200 | 3,628,800 | 354,000 | 81,000 | 1.0588 | 105.88 | estimated |
| orchestration | 32 | 124,800 | 499,200 | 192,000 | 25,600 | 1.6282 | 162.82 | tier-default |
| **Total** | **218** | **4,846,800** | **19,387,200** | **1,538,000** | **361,600** | **16.8725** | **1,687.25** | |

### Derivation

```text
Squad Implementor.md — 3 block(s) — identities: 83816158,5a6de0c0,0d200402
Squad Lead.md — 1 block(s) — identities: a88ac30c
Squad Researcher.md — 1 block(s) — identities: f5b9d142
Squad Reviewer.md — 3 block(s) — identities: 01d2d0d8,7b74b101,859aa948
Squad Scribe.md — 8 block(s) — identities: 129f8502,a124c224,5a3e5c54,c233b740,ac9fa201,01137959,19c304ea,220bf62b
researcher     turns 12           148800 × 2.00 + 595200 × 0.10 + 84000 × 2.50 + 15000 × 10.00 = 717120 / 1e6 = 0.7171
lead           turns 15           264000 × 2.00 + 1056000 × 0.10 + 116000 × 2.50 + 30000 × 10.00 = 1223600 / 1e6 = 1.2236
developer      turns 35+35+35=105 3402000 × 2.00 + 13608000 × 0.10 + 792000 × 2.50 + 210000 × 10.00 = 12244800 / 1e6 = 12.2448
tester         turns 18+18+18=54  907200 × 0.50 + 3628800 × 0.05 + 354000 × 0.62 + 81000 × 2.50 = 1058790 / 1e6 = 1.0588
orchestration  turns 4+4+4+4+4+4+4+4=32 124800 × 3.00 + 499200 × 0.30 + 192000 × 3.75 + 25600 × 15.00 = 1628160 / 1e6 = 1.6282
                                                                                        total = 16.8725
```

> This is the initialization and fallback shape. Exact mode replaces `Turns` with
> `Requests`, `Est. Cost` / `Est. Credits` with `Exact Cost` / `Exact Credits`, and
> every row's basis with `exact-native`. Its input column is uncached billed input;
> cache read and cache write remain separate, so the four token columns are
> disjoint and reproduce native token-detail charges. The exact Attribution table
> uses `host-reported` and `native credits`; fallback Attribution preserves the
> existing model-source ladder. 1 AI credit = 0.01 USD.
>
> The `<file>.md — <n> block(s) — identities: <hash>,<hash>,...` line uses the history file's basename, without a `history/` prefix. It is the ledger's own record of which `###` entries it has already folded in, one short deterministic hash per entry in file order. The initial Scribe-only seed records an empty prefix; the first ledger write replaces it with actual identities. A rewrite that finds this run's recorded identities are not an ordered prefix of the file's current identities — same count but different hashes, or fewer current entries than recorded — means an entry was overwritten, reordered, or removed since the last rewrite rather than only appended to, and `Measure-SquadLedger.ps1 -Check` (or render mode) refuses rather than silently accepting it. A pre-existing ledger with no recorded identities at all (an older-format entry) only warns when checked plainly; it never fails on that account alone. But the Scribe's own post-write self-check always runs `-Check` together with `-ExpectedHistoryCounts` (*scribe-procedure.md*'s Write-Completeness Self-Check Step 3), and in that combination a Derivation missing identities entirely, or missing them for only some of the touched files (a partial paste), FAILS instead of warning — that call always follows a fresh write, so a missing or partial paste there is this run's own defect, never a genuinely old ledger.

## Unit Economics (value)

| Measure | Value | Label |
| ------- | ----- | ----- |
| Deliverables produced | 3 | derived |
| Accepted by an independent review | 0 | derived |
| Rejected | 0 | derived |
| Unreviewed | 3 | derived |
| Dispatches (excluding Scribe) | 8 | derived |
| Rework dispatches | 2 | derived |
| First-pass yield | n/a | derived |
| Est. credits per accepted deliverable | n/a | estimated |
| Rework share of est. credits | 48.4% | estimated |
| Orchestration share of est. credits | 9.6% | estimated |

Value is counted only for deliverables an independent review-class verdict accepted; a produced but unaccepted deliverable adds cost and no value. A review that names deliverables covers only those it names. Rework counts a repeat of the same agent and deliverable path only: a fix by a different agent, to a different file, or with no deliverable path is not counted, so the rework figures are a floor. Compare runs only for like work, using medians of several runs. Source: FinOps Foundation unit-economics KPIs (cost per unit of value, error and retry waste).

## Cost Comparison (illustrative)

This run consumed an estimated **$16.8725 (~1687.25 AI credits)** across 4 specialized agent(s) (squad figure only; native per-role attribution unavailable; manual baseline and saving unavailable).
