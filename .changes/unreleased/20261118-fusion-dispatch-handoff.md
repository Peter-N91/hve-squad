---
bump: patch
type: Fixed
---

- **Copilot Fusion routes could be passed as unsupported standalone models.** Dispatch plans now choose a native request from the host's advertised capabilities, and handoffs record the requested tier separately from the reported model used for usage accounting (`squad-src/.github/skills/squad/scripts/New-SquadDispatchPlan.ps1`, `squad-src/.github/skills/squad/scripts/Write-SquadHandoff.ps1`).
