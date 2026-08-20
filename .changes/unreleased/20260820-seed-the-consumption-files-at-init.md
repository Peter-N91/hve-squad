---
bump: patch
type: Fixed
---

- **A squad seeded every state file except the two the consumption ledger needs.**
  Init created `team.md`, `routing.md`, `decisions.md`, `notifications.md`, `state.json`, and
  `history/`, and left `consumption.md` and `consumption-rates.md` to be created by whichever later
  step first wrote a cost. Nothing guaranteed that step ever ran, so a squad could reach its fourth
  stage with a full `decisions.md`, artifacts on disk, and no ledger and no rate table at all. The
  rate table is the only source of token rates, so its absence also stopped the Scribe pricing a
  dispatch — and because a history append and its consumption block are inseparable, the append it
  could not pair was dropped too, leaving `history/Squad Researcher.md` and `history/Squad Lead.md`
  sitting at their headers while research and plan artifacts existed beside them. Both files are now
  part of the Init seed, in the coordinator's list, the Scribe's list, the payload-to-step map, and
  federation expansion (`squad-src/.github/agents/squad/squad-coordinator.agent.md`,
  `squad-src/.github/agents/squad/squad-scribe.agent.md`,
  `squad-src/.github/skills/squad/references/scribe-procedure.md`,
  `squad-src/.github/skills/squad/references/operating-procedure.md`,
  `squad-src/.github/instructions/squad/squad-federation.instructions.md`).
- **"Inseparable" was read as permission to write neither.** The rule pairing a history append with
  its consumption block is there to stop an unpriced dispatch, not to suppress the dispatch record
  when pricing is unavailable. It now says which way to resolve: seed the rate table, or record
  `unknown` at the tier fallback, and append either way. A silent history is indistinguishable from a
  stage that never ran, so the run failed its own proof-of-dispatch check over a missing file the
  Scribe was able to create (`squad-src/.github/skills/squad/references/scribe-procedure.md`).
