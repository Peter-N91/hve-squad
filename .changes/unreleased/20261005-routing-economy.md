---
bump: minor
type: Added
---

- **Opt-in `routing=economy` for cheaper implementation picks.** A new routing mode, persisted as `Model routing: economy` in `team.md`, runs the same resolver as `ranked` with a cost-first order for mapped `implementation`-class roles only: the lowest-Blended id at fit 2 or better within the role's own Model Tier floor. Review-class and every other role keep their `ranked` pick, and no floor is relaxed. The pick is written into the `Model` cell like a ranked pick and every dispatch copies the cell. After a `Fail` verdict, a Critical or High finding, or a `blocked` owner, that owner is re-dispatched once on its `ranked` pick, which the Scribe writes into the cell first; the next re-rank resets it. `off` stays the default and still omits `model`. `scripts/Resolve-SquadModelRoute.ps1 -Mode economy` returns the pick, the escalation id, and the agent's pin (now also found in an installed plugin's `agents/` folder). Changed in `references/model-routing.md` (new *Economy Mode*), the coordinator, both `/squad` prompts, `squad-roster.instructions.md`, and the files that list the routing modes.
