---
bump: minor
type: Added
---

- **Roster split**: Cast Catalog, External Cast, and Building a Custom Roster sections moved to canonical `skills/squad/references/roster-catalog.md` (read on demand; inline safety summary, Dispatchability, and Profiles/Packs remain in `squad-roster.instructions.md`)
- **Ledger determinism guards**: `Measure-SquadLedger.ps1 -Check` now fails when ledger total diverges from `state.json` `currentRun` (missing/unparseable state.json fails; a federation root marked by `federation.md` is logged not-applicable), or when recorded per-file ordered block identities are overwritten/removed (per-history-file ordered block identities recorded in Derivation); a plain `-Check` (no `-ExpectedHistoryCounts`) only warns on legacy ledgers with no recorded identities. Combined with `-ExpectedHistoryCounts` — the Scribe's own post-write self-check — a Derivation missing identities entirely, or missing them for only some of the touched files (a partial paste), fails instead of warning
- **Scribe Self-Check**: Write-Completeness Self-Check now runs exactly once per hand-off after the last write, not per append; `currentRun` totals copied from helper output
- **Model routing rule**: "The Scribe must not inherit the frontier session model" (its `model:` frontmatter pins Claude Haiku 4.5; `bookkeeping` assignment class floors at seeded `fast` Model Tier; no routing input nor the no-policy default ever substitutes)
- **Performance measurement**: Static byte-budget reduction demonstrated (vscode-apm ~96–98 KB drop for coordinator/federation/Scribe hot core; plugin-cli ~flat +0.5–1.9 KB); wall-clock improvement not demonstrated (prior live benchmark voided). Perf label: static byte / step reduction; wall-clock improvement not demonstrated.
- **Deferred**: Single/Cascade/Critique routing patterns, task-class table, batched stage writes, verbatim scribe-append/lifecycle split, moving Profiles/Packs cold, merging routing files, live instrumented wall-clock re-measurement (branch `feature/adaptive-model-routing-performance` 3a26f5d not adopted)
