---
bump: patch
type: Changed
---

- **The cost ceiling warned only after estimated spend had already accumulated.** Cost Preflight now builds a conservative demand manifest before work dispatch, applies eligible calibration plus a factor-of-three reserve, and persists a reproducible decision. Confirmed initialization is recorded setup spend outside admission. An `over-ceiling` forecast offers stop or bounded proceed; approved work runs in sequential units and stops new work when accumulated estimated spend reaches the ceiling. Omitted input inherits inside the same run, `cost-ceiling=unset` removes the guard, and a new run without a value is ungated. Ordinary federation routing applies an independent ceiling to every selected sub-squad; only untargeted federation autopilot uses one aggregate root ceiling, rate table, and cumulative multi-round meta total (`squad-src/.github/skills/squad/references/consumption.md`, `squad-src/.github/skills/squad/references/gates-and-modes.md`).