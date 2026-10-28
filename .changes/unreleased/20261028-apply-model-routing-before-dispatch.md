---
bump: patch
type: Fixed
---

- **Explicit model routing could be skipped on quick and single-role requests.** Carry requested policy separately from saved policy, apply the existing routing transaction during dispatch preparation, and require its readiness result in both coordinator paths. The shared APM source also feeds the generated plugin; its dispatch guard now resolves native agent IDs and rejects missing active Model cells. Updated `Get-SquadDispatchBrief.ps1`, `New-SquadDispatchPlan.ps1`, coordinator contracts, and the plugin builder.
