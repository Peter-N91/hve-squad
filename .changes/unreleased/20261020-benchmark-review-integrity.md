---
bump: patch
type: Fixed
---

- **Benchmark review fixes preserve source and grader identity across saved-control comparisons**, remove deleted Squad files before source overlays, validate native session allowances before paid work, and document the actual shared stopping limits (`tests/lib/SquadInstall.psm1`, `tests/tier2/live-benchmark/`).
- **Release ancestor selection handles JSON-array pagination, and evidence suites run in CI through a PowerShell 7.5+ offline entry point.** Bash-specific release-guard tests follow the existing Windows/availability guard (`.github/workflows/tier2-benchmark.yml`, `.github/workflows/tier2-semantic.yml`, `tests/tier0/PrValidation.Tests.ps1`).
