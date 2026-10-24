---
bump: patch
type: Fixed
---

- **Fresh squad setup and reviewer capture preserve their declared metadata.** Empty initialization scaffolds are accepted without overwriting populated state, member roots retain no-deliverable sentinels, and requirements reviewers receive a seeded capture destination. Ordinary handoffs reject routing labels as actual models while preserving unresolved auto-session attribution (`Initialize-Squad.ps1`, `Write-SquadHandoff.ps1`, `seed-templates.md`, `requirements-quality.md`).
