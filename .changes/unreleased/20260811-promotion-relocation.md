---
bump: patch
type: Fixed
---

- **Promoting a single squad to a federation left the squad's own work behind and could delete it.**
  Promotion moved only the state tree, so every artifact produced before the promotion —
  `brd-sessions/`, `plans/`, `details/`, `research/`, `changes/` — stayed at the repository-root
  tracking paths while the roster's deliverable roots had already rebased under `members/<name>/`.
  Promotion now relocates those directories too, enumerated from disk rather than from the
  *Deliverable Roots* lookup table (which names the roots the cast writes today, not every directory
  a session produced) and confirmed with the user in Phase 1; `docs/` and `outputs/` stay at the
  repository root, and a Watch Mode promotion moves everything under `.copilot-tracking/` except
  `squad/` and records the list in its decision entry
  (`squad-src/.github/instructions/squad/squad-federation.instructions.md`,
  `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`,
  `squad-src/.github/agents/squad/squad-scribe.agent.md`).
- **A promotion could clear the source before writing the destination, then report it could not find
  the files to move.** Every move is now an explicit **copy → verify → delete-source** sequence, per
  file: write the destination, read it back, and only then remove the source. Nothing at the source
  is removed, cleared, or truncated before its verified destination copy exists, and a failed
  destination write stops the promotion with the source intact — a partially relocated tree is
  recoverable and a deleted source is not
  (`squad-src/.github/instructions/squad/squad-federation.instructions.md` *Copy, Verify, Then
  Delete*, `squad-src/.github/agents/squad/squad-scribe.agent.md` Step 10).
- **A promotion produced no consumption accounting, so the new federation reported a zero-cost first
  turn over a sub-squad carrying a populated ledger.** The Scribe now runs its consumption step for a
  promotion payload scoped to the relocated sub-squad root, rewrites `members/<name>/consumption.md`
  from the relocated history, and seeds the federation `state.json` `currentRun` totals from that
  ledger's total row. The Federation Coordinator verifies the relocation by reading
  `members/<name>/` back before confirming, rather than asserting success
  (`squad-src/.github/agents/squad/squad-scribe.agent.md`,
  `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`).
