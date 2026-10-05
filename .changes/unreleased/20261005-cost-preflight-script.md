---
bump: patch
type: Changed
---

- **The coordinator's one direct state write, the pre-dispatch Cost Preflight transaction, was model-composed.** It now runs only through the new `scripts/Set-SquadCostPreflight.ps1` (closed key set, compare-and-swap on `updated`, exact legacy schema bump, read-back). Without `pwsh` 7+ a configured ceiling is `cannot-confirm` and dispatches nothing. See `squad-src/.github/agents/squad/squad-coordinator.agent.md` and the floor and state instructions.
