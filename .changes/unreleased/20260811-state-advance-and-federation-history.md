---
bump: patch
type: Fixed
---

- **`state.json` was seeded at Init and then never advanced.** No Scribe step touched `updated`,
  `turn`, `mode`, `activeRoles`, or `openEscalations`, so a squad appended decisions and history
  every turn beside a status document still reading `turn: 0` — and in a federation, a routed turn
  left the federation's own `state.json` untouched entirely. A new Scribe **Step 12** advances the
  file on every turn that writes anything, as a read-modify-write that carries `schemaVersion`,
  `notify`, `trigger`, `currentRun.sessionModel`, and `currentRun.modelOverrides` forward instead of
  resetting them, and leaves the cost totals to the consumption step. Both coordinators now hand the
  advance on the same call that appends the logs, and both verify it before reporting the turn done
  (`squad-src/.github/agents/squad/squad-scribe.agent.md`,
  `squad-src/.github/agents/squad/squad-coordinator.agent.md`,
  `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`,
  `squad-src/.github/instructions/squad/squad-state.instructions.md`).
- **A federation root never got its `history/` directory.** The Scribe's history step defines the
  file as `history/<agent>.md` for a dispatched agent and requires a paired consumption block, so a
  federation-level entry — which names a sub-squad, not an agent, and whose cost is already recorded
  in that sub-squad's own ledger — fell outside the step and was silently dropped. The step now
  covers it explicitly as the one history append that stands alone, the federation coordinator's
  completion checklist catches a root that only grows its decision log, and the federation
  conventions state exactly which files a healthy federation root holds and which are legitimately
  absent (`squad-src/.github/agents/squad/squad-scribe.agent.md`,
  `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`,
  `squad-src/.github/instructions/squad/squad-federation.instructions.md`).
