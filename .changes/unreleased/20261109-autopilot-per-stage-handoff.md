---
bump: patch
type: Fixed
---

- **`mode=autopilot` was ignored on an already initialized squad, so every stage landed in one end-of-run hand-off.** The brief reads the squad's recorded mode, which stays `interactive` after a separate init, so the autopilot procedure never loaded. `Get-SquadDispatchBrief.ps1` now takes `-RequestedMode` and, for `autopilot`, names the required procedures and the per-stage hand-off rule. `Write-SquadHandoff.ps1` accepts `-Mode` on the single-dispatch form and refuses a multi-record payload under autopilot, so the rule is enforced the same way on VS Code, the CLI and the GitHub Copilot App (`squad-src/.github/skills/squad/scripts/Get-SquadDispatchBrief.ps1`, `squad-src/.github/skills/squad/scripts/Write-SquadHandoff.ps1`, `squad-src/.github/skills/squad/references/coordinator-runtime.md`).
