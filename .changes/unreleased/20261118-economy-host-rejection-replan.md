---
bump: patch
type: Fixed
---

- **Economy retries no longer consume the Ranked escalation after a native model rejection.** Host-rejected ids are excluded through `rejectedModels`, remaining roles are replanned cost-first within their floors, and the refreshed routing transaction and any required Cost Preflight complete before dispatch. Retries stop without a confirmed host model list; Manual never reuses a rejected pick (`squad-src/.github/skills/squad/scripts/Resolve-SquadModelRoute.ps1`, `squad-src/.github/skills/squad/scripts/New-SquadDispatchPlan.ps1`, and `squad-src/.github/skills/squad/references/economy-mode.md`).
