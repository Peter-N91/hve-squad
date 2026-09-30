---
bump: minor
type: Changed
---

- **The `graph-research` prompt was removed outright from hve-core.** It was never a dispatchable roster entry, only a user entry point the `researcher` role Selection Cue referenced for escalation; that reference now says so instead of naming a `/graph-research` command that no longer exists (`squad-src/.github/instructions/squad/squad-roster.instructions.md`). No agent, skill, or roster row required adaptation. `apm.yml` now pins hve-core `5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb`.
