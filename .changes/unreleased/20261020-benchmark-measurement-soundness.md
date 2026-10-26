---
bump: patch
type: Fixed
---

- **Benchmark acceptance no longer admits misleading successes.** Rejection probes require natural rejection rather than watchdog termination (`tests/tier2/live-benchmark/Test-EfficiencyTask.ps1`).
- **Resumed benchmark runs receive the full workflow allowance from initialization** while reserving independent-judge consumption and tracking cumulative native spending (`tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1`, `EfficiencyBenchmark.psm1`).
- **Numeric trial allowances avoid credential-parameter false positives without suppressing analysis or changing limits.** Baseline collection measures unmodified Squad source; benchmark-driven Scribe optimizations and dependent assertions are removed while native preparation, observational collection and independent quality gates remain. Modified-source observations stay separate historical evidence (`tests/tier2/live-benchmark/EfficiencyBenchmark.Tests.ps1`, `EfficiencyBenchmark.psm1`).
