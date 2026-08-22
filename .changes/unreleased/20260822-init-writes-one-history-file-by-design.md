---
bump: patch
type: Fixed
---

- **The contract failed Init for doing what the floor requires.** `SQ-09` asserted that Init leaves
  `history/` empty, while the floor states that the Scribe writes an orchestration block into
  `history/Squad Scribe.md` on every turn it writes state, **including Init**. Earlier runs happened
  not to comply and the contradiction stayed hidden; the run that finally complied was failed for
  it. The rule this protects is that no *agent* history file predates its dispatch — a seeded
  `history/Squad Researcher.md` is the defect, and the Scribe's own record of the Init turn is not a
  dispatch record. `SQ-09` now permits it and rejects everything else
  (`tests/tier1/StateContract.Tests.ps1`).

- **The calibration note was asserted against the wrong file.** The rule says that until the
  calibration factor has been reconciled once, *the ledger* carries an uncalibrated note — and the
  assertion searched `consumption-rates.md` for the word instead. Every seeded squad reported a
  finding it could not have avoided, including one whose ledger said `Calibration factor 1.00 (0
  reconciled runs)` in as many words. The check now reads the ledger, and the rates file's own shape
  is left to the assertion that already covers it.
