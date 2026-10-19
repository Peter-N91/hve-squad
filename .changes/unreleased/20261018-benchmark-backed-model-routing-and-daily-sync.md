---
bump: minor
type: Added
---

- Added a pinned, versioned model benchmark knowledge base (`references/model-benchmarks.md`), a daily sync generator and GitHub Actions workflow (`scripts/Sync-ModelBenchmarks.ps1`, `.github/workflows/sync-model-benchmarks.yml`), and updated `Resolve-SquadModelRoute.ps1` and `model-routing.md` so `routing=ranked` ranks by fresh class-mapped independent benchmark evidence first, records source and version in `Route rationale`, ignores `self-reported` scores for ranking, and falls back to `model-catalog.md` with a warning on missing, invalid, stale, or class-inapplicable evidence (#166).
- Added `HydraFusion Max` (`hydrafusion-max` / `hydrafusion`) to `model-catalog.md`, `consumption-rates-template.md`, `model-benchmarks.md`, `Write-SquadHandoff.ps1`, `Get-SquadDispatchBrief.ps1`, and `Measure-SquadLedger.ps1` with its cascade rate (`$0.360/1M` blended), `0.35x` token-efficiency estimator factor, host-reported token totals, and separately labelled calculated representative-blend costs and estimated standard-model counterfactuals in `consumption.md` (#166).
