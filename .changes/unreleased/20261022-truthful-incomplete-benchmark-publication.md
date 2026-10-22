---
bump: patch
type: Fixed
---

- **Incomplete benchmark campaigns no longer disappear behind export failures.** Offline campaign export preserves unavailable grades and accounting, immutable evidence hashes and known consumption; wizard finalization writes portable observations outside measured source. Unavailable comparisons now show independently validated historical and current observations without paired deltas or a passing verdict (`tests/tier2/live-benchmark/BenchmarkResults.psm1`, `Start-EfficiencyWizard.ps1`).
