---
bump: patch
type: Fixed
---

- **The consumption block's field names never reached the host that writes them.** A live single-turn
  run recorded `modelSource`, `pricedAs`, `internalTurns`, `grossInputTokens`, and `estimatedCostUsd`,
  invented `baseContext`, `growthPerTurn`, and `dispatchClass`, and omitted all four `*_rate` fields —
  three of sixteen contractual names survived. The literal shape lived only in the `squad` skill's
  `references/entry-schemas.md` and in `squad-state.instructions.md`, neither of which loads before
  squad state is already in play. The sixteen-field JSON block is now reproduced verbatim in
  `squad-floor.instructions.md`, the one file scoped to `**`, alongside the bare-number rule and the
  instruction not to translate it into camelCase or add fields
  (`squad-src/.github/instructions/squad/squad-floor.instructions.md`).
- **History files were headed with the bare agent name.** Files came back headed `# Squad Researcher`
  rather than `# History: Squad Researcher` — the exact failure the schema file warns about, which
  reads to a later turn as a file with no heading at all. The literal heading is now in the floor.
- **Costs were still being judged rather than derived.** A promotion block recorded
  `est_cost_usd: 0.047` where its own four token counts times its own four rates give `0.04224`, and
  `state.json` carried one dispatch's cost as the whole run's. The floor already required the figure
  to reproduce from the block; it now carries the four-product worked example that was stranded in
  `references/scribe-procedure.md`, plus the rule that `currentRun`'s totals equal the ledger total.
- **Promoted sub-squads got a hand-written rate table.** Federation promotion seeded a 957-byte
  `consumption-rates.md` with four model rows and no tier-fallback table, no dispatch-size estimator,
  and no calibration block, leaving the Scribe pricing from a table missing what it needs. The floor
  now states that the file is copied verbatim from the skill template at Init and at every sub-squad
  seeding or promotion, and that all four sections are load-bearing.
- **The ledger kept its seed rows and its seed run id.** A turn-2 ledger still read
  `Run: init-2026-08-20` and carried zero rows for `lead`, `developer`, and `orchestration`, and a
  promoted ledger labelled its overhead row `scribe`. The floor now fixes `orchestration` as the row
  label in both tables and states that the rewrite reads every block in `history/` — so an
  undispatched role has no row rather than a zero row, and the total is the run's, not the turn's.
