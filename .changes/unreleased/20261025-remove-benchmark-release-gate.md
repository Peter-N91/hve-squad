---
bump: patch
type: Removed
---

- **Releases no longer depend on a recorded benchmark comparison.** The Release workflow's `run_benchmark` input and benchmark gate, `tier2-benchmark.yml`, the efficiency wizard, the recorded-series export, study and comparison modules, and the stored records, policy and report files are removed. Each branch carries its own score instead (`.github/workflows/release.yml`, `tests/tier2/live-benchmark/`, `benchmarks/efficiency/`).
