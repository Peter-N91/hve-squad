---
bump: minor
type: Changed
---

- **The `lead` role lost its `RPI Planner` alternate.** `hve-core@14e46010407edaa194bd2bba3d4e100d8707739c` removed `RPI Planner` outright with no replacement agent; it shared the same delegated-worker input contract (a required parent plan artifact, one assigned phase, a bounded write boundary) that already excludes `RPI Researcher` from the roster, so it was never a valid plain role dispatch target. The `lead` role's cast catalog row, the roster example, the `seed-templates.md` template, and the `agents:` frontmatter of both `squad-coordinator.agent.md` and `squad-federation-coordinator.agent.md` now drop it with no substitute, since `Squad Lead` already authors and revises every phase of its own plan directly. No new squad-owned charter was needed.
