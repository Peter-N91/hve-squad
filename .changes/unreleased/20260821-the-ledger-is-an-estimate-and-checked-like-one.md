---
bump: minor
type: Changed
---

- **The ledger's arithmetic checks now measure orders of magnitude, not digits.** Every figure in
  `consumption.md` is an estimate derived from a token-size model, because no per-dispatch telemetry
  exists — so failing a run because a row said `0.1395` where its own tokens derive to `0.1301`
  reported a defect nobody could act on and buried the ones that mattered. Row costs, column totals,
  the orchestration row, the run total, and the `state.json` reconciliation are now compared within a
  factor of three, which still rejects the documented corruption — a factor-of-ten slip from
  dividing by `1e6` twice — while tolerating drift on a number that was estimated in the first place
  (`tests/tier1/StateContract.Tests.ps1`).

- **Structure stayed strict, because a missing row loses a role rather than mis-stating one.** A new
  assertion requires a ledger row for every role that was dispatched, which is what a total silently
  summed over the wrong rows used to be a proxy for. The reader also joins the two tables on the
  role name with any trailing annotation stripped, so a row labelled `orchestration (Turns 1-3)`
  still prices against its Attribution row instead of taking the whole ledger down with it.

- **The Cost Comparison section is now required and must name the saving.** A live run replaced it
  with a per-phase breakdown — reporting what was spent and dropping the only number that answers
  why a squad was run at all. The section now states what the run cost, what the manual baseline
  would have cost, and the saving as a percentage, along with the iteration count and baseline model
  it assumed so a reader can disagree with the assumption rather than only with the answer. A
  breakdown may be added below it and never in place of it
  (`squad-src/.github/instructions/squad/squad-floor.instructions.md`,
  `squad-src/.github/skills/squad/references/consumption.md`,
  `squad-src/.github/skills/squad/references/scribe-procedure.md`).
