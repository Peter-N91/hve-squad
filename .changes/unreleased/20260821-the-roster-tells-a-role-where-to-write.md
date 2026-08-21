---
bump: patch
type: Fixed
---

- **The `Deliverable Root` column had no force, so customizing it did nothing.** A live Copilot CLI
  run declared five roles' output locations in `team.md` and every one of the five wrote somewhere
  else — four to `.copilot-tracking/details/`, the convention baked into their own agent
  definitions, and the fifth collapsing a `<date>/` directory segment into a filename prefix. The
  roster is the only place an operator can steer where a squad's output lands, and it was being read
  as advisory. The floor now makes the cell binding: it overrides the path convention in the
  dispatched agent's own definition, a `<date>` or `<slug>` segment is a directory rather than a
  filename prefix, and a role that cannot use the root it was given escalates instead of choosing
  one it prefers (`squad-src/.github/instructions/squad/squad-floor.instructions.md`).

- **A stage produced its artifact and vanished from the record.** In the same run the `lead` role
  wrote a 16 KB implementation plan that had no `history/Squad Lead.md`, no ledger row, no mention in
  `decisions.md`, and no membership in `state.json`'s `activeRoles` — the coordinator assembled the
  run's history at the end from memory and dropped the stage that had run earliest. `state.json` and
  the ledger agreed with each other and with nothing that happened. Dispatches are now handed over
  one payload at a time as each returns, and proof of dispatch reconciles both directions: every
  `Deliverable:` path names a file that exists, and every artifact under a role's Deliverable Root is
  claimed by some history entry. An unclaimed artifact is a stop, not a warning.

- **A stage could report itself complete having written nothing.** A live run recorded
  `Deliverable: N/A — inline verdict, no review artifact file written` twice, and the review stage
  passed every check: an entry that names no path leaves the existence check with nothing to reject.
  The floor now states that `N/A`, `inline verdict`, `no artifact written`, and a missing
  `Deliverable:` line are the same statement — the stage produced nothing the next one can read — and
  that a role whose output is a judgment writes that judgment to a file at its Deliverable Root. A
  verdict that exists only in a chat turn is gone when the turn ends, and the gate depending on it
  has nothing to open.

- **A consumption block could price one model and report another.** The same run recorded a block
  carrying Claude Sonnet 5's four rate fields, a `model_tier` of `fast`, and a cost derived at Claude
  Sonnet 4.6's rates — internally contradictory and reproducible by nobody. The floor now fixes
  `model_tier` to the `Tier` cell of the row `priced_as` names, and requires the rates recorded and
  the rates multiplied by to be the same four from that one row. Two further guards join them: a
  block whose token counts match one already in `history/` was sized by copying rather than from the
  dispatch in hand, and the ledger's total row is summed down every column — turns and all four token
  columns, not the cost column alone — because the row a carried-forward total drops is the short one
  belonging to a role dispatched on an earlier turn.

- **An orchestration entry had a block template but no entry template.** `entry-schemas.md` gave a
  literal shape for a dispatch entry and only a sentence for an orchestration one, so the Scribe
  improvised the surrounding prose and the turn number and task description leaked into the JSON as
  `turn` and `task` — breaking the closed sixteen-field set and dropping the block out of the ledger
  rewrite. Both the floor and the schema reference now carry the literal orchestration entry shape,
  with the prose fields those two values belong in
  (`squad-src/.github/skills/squad/references/entry-schemas.md`).

- **A promotion left every artifact reference in `history/` pointing at nothing.** Federation
  promotion moves the deliverables and rebases the roster's `Deliverable Root` cells, but the
  `Deliverable:` paths already recorded in `history/` still name the pre-promotion locations — and
  cannot simply be corrected, because those files are append-only and move byte-for-byte. The
  promotion now records the relocation as one prefix mapping line per moved directory
  (`.copilot-tracking/<dir>/ → .copilot-tracking/squad/members/<name>/<dir>/`) rather than as prose,
  which is what makes a pre-promotion path resolvable again; the floor states that an entry is
  resolved through that mapping and never edited to match. Path comparison in the Tier 1 contract is
  correspondingly promotion-invariant, so a promoted squad reports the roles that wrote to the wrong
  folder without also reporting every entry the promotion left behind
  (`squad-src/.github/skills/squad/references/scribe-procedure.md`).

- **The Tier 1 contract enforced none of the above, and the harness could not have shown it.**
  The contract asserted no deliverable existed on disk, and the live harness captured only the squad
  root — so a scenario's research artifact, which lands beside that root rather than inside it, was
  never uploaded with the results. A squad writing immaculate ledgers about work it never did would
  have passed green. The contract gains `SQ-12` (every dispatch entry names an artifact, that
  artifact exists, it sits under its role's root, and nothing under a root is left unclaimed) plus
  assertions for tier coherence, copied sizing, and column-wise ledger
  totals; the harness now captures the whole `.copilot-tracking/` tree under that same name, so an
  uploaded result replays against the same path resolver the run used. The mutation self-check grows
  from 20 cases to 26, one per new rule (`tests/tier1/`).
