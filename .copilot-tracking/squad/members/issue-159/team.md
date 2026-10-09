---
description: "Squad roster for sub-squad issue-159"
---

# Squad Roster (issue-159)

## Members

| Role      | Member Name | Agent Name (Primary) | Alternate Agents | Invocation          | Model Tier | Deliverable Root            |
| --------- | ----------- | --------------------- | ------------------ | ------------------- | ---------- | ---------------------------- |
| researcher|             | Squad Researcher       |                    | runSubagent / task | default    | .copilot-tracking/research/   |
| lead      |             | Squad Lead             |                    | runSubagent / task | default    | .copilot-tracking/plans/      |
| developer |             | Squad Implementor      |                    | runSubagent / task | default    | .copilot-tracking/changes/    |
| tester    |             | Squad Reviewer         |                    | runSubagent / task | fast       | .copilot-tracking/reviews/    |
| scribe    |             | Squad Scribe           |                    | runSubagent / task | fast       | (squad state)                 |

## Notes

This sub-squad was created under Watch Mode autopilot for `Peter-N91/hve-squad#159` ("Adapt squad cast to hve-core af0e654"). The task is a mechanical-but-breaking hve-core sync adaptation: repoint `squad-src/` roster bindings so every Primary resolves to a dispatchable agent, move the hve-core pin, and record a minor change fragment. The execution host for this run exposes a single coordinating turn with no separate `runSubagent`/`task` dispatch runtime reachable from this harness; per *Dispatch Discipline* this is recorded as a deviation rather than concealed — see `decisions.md` for the honesty note and the single orchestration-only consumption entry in `history/Squad Scribe.md`.
