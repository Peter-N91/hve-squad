---
bump: patch
type: Fixed
---

- **The ledger asserted costs its own numbers did not support.** A live run priced a `lead` row at
  `0.1428` against tokens that derive to `0.0989` — a 44% overstatement — and priced `orchestration`
  wrong in the same rewrite. The rule was already emphatic and the arithmetic was still wrong,
  because it was done invisibly: four products, a sum, and a divide, collapsed into one number with
  nothing in the file to check it against. The ledger now carries a `### Derivation` block under
  Usage & Cost, one line per row, with the four products written out before the sum. Written
  products cost four numbers and turn a silent miscalculation into a visible one, and the state
  contract now rejects a priced row that has no derivation line
  (`squad-src/.github/instructions/squad/squad-floor.instructions.md`,
  `squad-src/.github/skills/squad/references/consumption.md`,
  `squad-src/.github/skills/squad/references/scribe-procedure.md`).

- **The run total rounded itself out of agreement with `state.json`.** The ledger template carried
  `**$0.00**` in the total's cost cell while every row above it carried four decimals, so a run
  totalling `0.2151` was written `$0.22` and the reconciliation against `state.json` failed by
  construction — a gap every later comparison inherited. The total's cost cell is now a bare
  four-decimal number matching the rows above it.
