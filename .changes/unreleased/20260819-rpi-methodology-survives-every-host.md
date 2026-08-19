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
