---
bump: minor
type: Fixed
---

- **A run reported ten dispatched roles over a `history/` holding two files.** An autopilot run on a
  live repository produced research, a plan, an architecture, a council verdict, an IaC scaffold, a
  cost model, a security review, a closing review, and a remediation — and left no
  `history/<agent>.md` for any of the roles that supposedly produced them. The rule it broke is
  stated in six files. Prose was not the missing ingredient, so three mechanisms replace it.

  **The ledger's row set is now a function of `history/`, not of the payload.** The Scribe lists the
  directory and writes that listing — one line per file with its block count — into the
  `### Derivation` block *before* any row, then writes a row for each enumerated file and for nothing
  else. A role that left no file gets no row, so the eleven-row ledger that hid the gap is no longer
  writable. A payload naming a role the listing does not comes back as a discrepancy in the Scribe's
  confirmation note (`scribe-procedure.md`).

  **The autopilot run summary now reports the gap itself.** `## Stages` gains a `Dispatch Record`
  column filled from `history/`, and a stage with no file carries `— none recorded`. Any such cell
  forces `Outcome: incomplete (<n> stage(s) without a dispatch record)`. The Scribe is the only
  writer of history, so it is the only participant that can say which stages actually ran — and the
  coordinator's account of the run is exactly what cannot be trusted to say so
  (`entry-schemas.md`, `scribe-procedure.md`).

  **The per-stage gate is reachable again.** Autopilot now hands off to the Scribe once per stage
  rather than once per pipeline, and `state.json` advances per stage. The observed run collapsed a
  fan-out, a security review, a closing review, and a remediation into a single turn, which left no
  point at which stage N's missing history entry could block stage N+1
  (`squad-autopilot.instructions.md`, `squad-coordinator.agent.md`).

- **The contract could not see an invented ledger row.** `carries no row for a role that was never
  dispatched` only catches rows costed at zero, and every invented row in the observed run carried a
  plausible figure. `every ledger row has a history file behind it` resolves each row through the
  roster and requires one of its agents to hold a history file, which is the assertion that fails
  that tree (`tests/tier1/StateContract.Tests.ps1`, `tests/tier1/SquadState.psm1`).
