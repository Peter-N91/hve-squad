---
bump: patch
type: Fixed
---

- **The Research → Plan → Implement → Review spine stopped running on the Copilot CLI and the app.**
  The Implementation Gate, the review follow-through, and the autopilot artifact gates lived only in
  `squad-routing.instructions.md` and `squad-autopilot.instructions.md`, both gated on
  `applyTo: '**/.copilot-tracking/squad/**'`. Those files never auto-apply on the CLI or the app, and
  apply in VS Code only once a squad-state path is already in context — so the coordinator classified a
  request, dispatched the deliverable's owner, and skipped research, plan, council, and review while the
  finished deliverable made the run look complete. The procedures now live in
  `references/gates-and-modes.md`, which every coordinator reads by path on every turn and every host, and
  the spine is restated in the always-on `squad-floor.instructions.md`
  (`squad-src/.github/skills/squad/references/gates-and-modes.md`,
  `squad-src/.github/instructions/squad/squad-floor.instructions.md`).
- **Step 3 of the coordinator promised four dispatch branches and listed three.**
  The Implementation Gate branch was dropped when the agent was compacted, leaving no instruction to check
  for research and plan artifacts before dispatching a producing role. The branch is restored, and it now
  names the deliverable-producing roles explicitly so a BRD, roadmap, journey map, experiment plan, or deck
  is treated as an output of the methodology rather than a shortcut around it
  (`squad-src/.github/agents/squad/squad-coordinator.agent.md`).
- **An intake verdict could report outstanding blocking gaps and still permit dispatch.**
  `Ready-With-Gaps` means zero blocking gaps, but that rule was only in the `applyTo`-gated intake
  instructions, so a run recorded five blocking gaps as "riskiest assumptions" and proceeded. The label is
  now decided by the blocking-gap count in the reference the coordinator always reads, and an unanswered
  blocking question is put to the user — in the response text on a host with no question tool — instead of
  being converted into an assumption
  (`squad-src/.github/skills/squad/references/gates-and-modes.md`).
- **The seeded `routing.md` differed per host because the canonical table mixed roles with agent names.**
  Ten rows in a column headed `Role(s)` carried agent names (`Security Planner`, `UX UI Designer`,
  `PRD Builder`, `DT Coach`, `Experiment Designer`, `System Architecture Reviewer`, `RAI Planner`,
  `Finding Deep Verifier`, `Squad IaC Author`, `Squad Deployer`), so one host normalized them to role ids
  and another copied them verbatim. An agent name there resolves to no `team.md` row, which silently drops
  that row's `Member Name`, `Model Tier`, Selection Cues, and `Deliverable Root`. Every row now carries a
  role id, and both the canonical table and the seed template say why
  (`squad-src/.github/instructions/squad/squad-routing.instructions.md`,
  `squad-src/.github/skills/squad/references/seed-templates.md`).
- **A hand-edited `Deliverable Root` was ignored by any agent that builds its own output path.**
  The `presenter` root moved to `ppt-prezi/` in `team.md` and the deck still landed in `ppt/`, because the
  `powerpoint` pipeline derives `<date>/<deck-slug>/` itself and takes the parent as an argument — naming
  the cell in the dispatch prose was not enough. The coordinator now passes the root *as the output
  argument*, the roster records that some agents need it that way, and the brand-template instructions no
  longer stop applying when the deck root is renamed
  (`squad-src/.github/agents/squad/squad-coordinator.agent.md`,
  `squad-src/.github/instructions/squad/squad-roster.instructions.md`,
  `squad-src/.github/instructions/squad/pptx-brand-template.instructions.md`).
- **Both coordinators sat within 250 characters of the 30,000-character agent-body cap.**
  Under that cap the body is truncated outside VS Code, so any addition would have silently cut the
  closing sections — which is what makes the limit dangerous rather than merely tight. Sections that
  restated the always-on floor, the Scribe's own consumption procedure, and the skill's gate references
  were collapsed, leaving 1,519 characters of headroom on the coordinator and 813 on the federation
  coordinator with the new gate procedures included
  (`squad-src/.github/agents/squad/squad-coordinator.agent.md`,
  `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`).
- **The `orchestration` ledger row had no storage, so it reset on every rewrite.**
  The Scribe rewrites `consumption.md` from the consumption blocks recorded in `history/*.md`, and the
  `orchestration` row is defined as the sum of every recorded orchestration block — but no step ever said
  to write one. With nothing to read back, the row could only reflect the turn in hand, so a run
  under-reported its own overhead by every turn that came before. Orchestration now appends a
  `#### Consumption — Orchestration` block to `history/Squad Scribe.md`, which is also why the Scribe was
  missing from `history/` altogether
  (`squad-src/.github/skills/squad/references/scribe-procedure.md`,
  `squad-src/.github/skills/squad/references/consumption.md`).
- **The history filename convention contradicted itself, so hosts named the same file differently.**
  `entry-schemas.md` mandated the agent's display name (`history/Squad Researcher.md`) while the promotion
  procedure wrote `history/scribe.md`, and one host produced `squad-scribe.md`. A renamed file reads as a
  missing entry and drops that agent from every later ledger rewrite. The rule is now stated once,
  verbatim-display-name, and hoisted into the always-on floor so it binds before any reference file loads
  (`squad-src/.github/skills/squad/references/entry-schemas.md`,
  `squad-src/.github/instructions/squad/squad-floor.instructions.md`).
- **A ledger could stay headed `Run: init-001` while history held dispatch records.**
  Moving off the seed state was implied by "the seed note must not remain" but the run id itself was never
  named, and a stale id reads as a healthy ledger for a squad that only ever seeded. Rewriting the id is
  now an explicit obligation of the ledger rewrite
  (`squad-src/.github/skills/squad/references/scribe-procedure.md`).
