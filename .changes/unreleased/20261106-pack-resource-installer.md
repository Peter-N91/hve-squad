---
bump: patch
type: Fixed
---

- **Selected Foundry and Fabric packs could initialize without installing their registered skills.** Single-squad and federation Init/expansion now inventory registered skills, execute only registry-approved installers after consent, preserve prerequisites as separate approvals, and stop before state publication until a required host reload lets final preflight record each skill as host-visible `available` or explicitly `declined`; unattended Watch drops or escalates packs whose skills are not host-visible (`Get-SquadInitContext.ps1`, `Install-SquadPackResources.ps1`, `Initialize-Squad.ps1`, `SquadWatch.Delivery.ps1`).
