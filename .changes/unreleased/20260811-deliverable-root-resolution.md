---
bump: patch
type: Fixed
---

- **A federated sub-squad's artifacts could still be created outside the member.** The *Deliverable
  Roots* table is now explicitly `squadRoot`-relative, and the Scribe resolves each root against the
  `squadRoot` it was handed **at seed time** before writing it into the roster — so a sub-squad's
  `team.md` reads `.copilot-tracking/squad/members/product/plans/` rather than the bare
  `.copilot-tracking/plans/`, and its research, plans, PRDs, changes, and reviews are created inside
  the member. Federation Init and Expansion verify the seeded roster before moving on, and a
  promotion rebases the relocated roster's cells so every role keeps pointing at its own relocated
  artifacts. `docs/` and `outputs/` remain the two exceptions and stay at the repository root
  (`squad-src/.github/instructions/squad/squad-roster.instructions.md`,
  `squad-src/.github/agents/squad/squad-scribe.agent.md`,
  `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`).
- **Editing a role's `Deliverable Root` in `team.md` had no defined effect.** The roster cell is now
  the running value and the table is only the seed-time default: the coordinator states each
  dispatch's write path from the row it just resolved, the Artifact Gate looks for the artifact at
  that same cell, and a roster refresh preserves an edited cell instead of normalizing it back. A
  consumer pointing a role at their own directory therefore takes effect on the very next dispatch
  with no reseed (`squad-src/.github/instructions/squad/squad-roster.instructions.md`,
  `squad-src/.github/agents/squad/squad-coordinator.agent.md`,
  `squad-src/.github/agents/squad/squad-researcher.agent.md`).
- **`/squad-document` is unaffected by the rebasing and now reads the squad's deliverables.** Its
  default output stays at the repository-root `docs/`, which the rebasing rule already exempts, and
  that exemption is stated where the path is derived so a future change does not rebase it under a
  sub-squad. Its search step also resolves the `Deliverable Root` paths from `team.md` rather than
  assuming the repository-root tracking paths, so a federated run grounds on the sub-squad's own
  artifacts (`squad-src/.github/prompts/squad/squad-document.prompt.md`).
