---
bump: patch
type: Fixed
---

- **Benchmark review fixes preserve source and grader identity across saved-control comparisons**, remove deleted Squad files before source overlays, validate native session allowances before paid work, and document the actual shared stopping limits (`tests/lib/SquadInstall.psm1`, `tests/tier2/live-benchmark/`).
- **Bash-specific release-guard tests follow the existing Windows/availability guard** (`tests/tier0/PrValidation.Tests.ps1`).
