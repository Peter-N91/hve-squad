---
bump: minor
type: Added
---

- **Ranked selects comparable task capability before price; Economy selects the lowest known price after qualification.** Shared policy `squad-capability-v3` separates result, acquisition, verification and generation dates: older verified results remain usable, while unverified legacy records, wrong model versions and incompatible harnesses remain excluded. Versioned implementation panels are selected by snapshot-wide coverage, not winners; reduced SciCode evidence is labeled and has its own Economy minimum. The generator preserves provenance and source precision, verification changes affect the digest, and offline resolver/brief diagnostics expose panels, dates, exact exclusions and fallbacks. Fast floors, protected roles, pins, consent, review gates and the one persisted Ranked escalation remain intact (#166).
- Added `HydraFusion Max` (`hydrafusion-max` / `hydrafusion`) to `model-catalog.md`, `consumption-rates-template.md`, `model-benchmarks.md`, `Write-SquadHandoff.ps1`, `Get-SquadDispatchBrief.ps1`, and `Measure-SquadLedger.ps1` with its cascade rate (`$0.360/1M` blended), `0.35x` token-efficiency estimator factor, host-reported token totals, and separately labelled calculated representative-blend costs and estimated standard-model counterfactuals in `consumption.md` (#166).
