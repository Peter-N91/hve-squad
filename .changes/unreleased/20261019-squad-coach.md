---
bump: patch
type: Added
---

- **Beginners had to understand Squad terminology before choosing a setup.** The new advisory-only
  Squad Coach discovers workflows from installed code and documentation, recommends the simplest
  sufficient setup, and returns preparation checklists and detailed A-to-Z runbooks with owning agents,
  exact messages, expected outputs, approvals, and source citations without changing state. A read-only
  PowerShell helper inventories current sources without a feature checklist. VS Code, CLI, and App
  guidance consistently selects agents and uses prefix-free messages. Plugin coaching uses a manual
  handoff and is advertised only when the selected source contains its agent and prompt; source-mode
  installs handle paired dependencies with the same package name
  (`squad-src/.github/agents/squad/squad-coach.agent.md`,
  `squad-src/.github/skills/squad/scripts/Get-SquadCoachContext.ps1`, `scripts/Build-SquadPlugin.ps1`).
