---
bump: patch
type: Fixed
---

- **The ledger's `Turns` column was specified for one dispatch and asserted as a sum.** Every rule
  about accumulation named "the four token columns", and the only definition of `Turns` described
  "the turn count for the dispatch" — singular — so nothing told the Scribe that a role dispatched
  twice at `15` and `4` carries `19`. One live run summed it and the next wrote `4`, because the
  spec left the reading to chance while the state contract required one of them. `Turns` now
  accumulates on the record exactly as the token columns do, in the floor, the Scribe procedure, and
  the ledger template, and the `### Derivation` block carries each row's turn sum written out as an
  addition beside its cost products — the fifth column is the one most often left at the last
  block's value precisely because it is the one that does not feed the cost
  (`squad-src/.github/instructions/squad/squad-floor.instructions.md`,
  `squad-src/.github/skills/squad/references/consumption.md`,
  `squad-src/.github/skills/squad/references/scribe-procedure.md`).

- **A deliverable was recorded with its path placeholder unsubstituted.** A live run logged
  `.copilot-tracking/research/<date>/concurrency-gap-reserve.md`, which names a directory literally
  called `<date>` — so the path pointed at nothing, and the existence check failed for a file that
  had been written correctly. The floor's `<date>`/`<slug>` rule now says to substitute the segment
  and never write the angle brackets.

- **The derivation check double-reported an existing defect.** A ledger seeded with zero rows for
  roles that were never dispatched failed both the assertion that rejects those rows outright and
  the new assertion that every priced row shows its arithmetic, naming the same roles twice and
  making one defect read as two. The derivation check now skips rows carrying no cost and leaves
  them to the assertion that exists to reject them (`tests/tier1/StateContract.Tests.ps1`).
