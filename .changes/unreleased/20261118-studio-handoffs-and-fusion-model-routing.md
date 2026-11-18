---
bump: patch
type: Fixed
---

- **Squad Studio handoffs could start a cold Scribe run, and Economy could pass Fusion tier IDs as standalone subagent models.** Ordinary persistence now stays on the direct validated writer, while Fusion routes emit the host-supported `auto_tier` form (`squad-src/.github/skills/squad/extensions/hve-squad-studio/lib/catalog.mjs`, `squad-src/.github/skills/squad/scripts/New-SquadDispatchPlan.ps1`).
