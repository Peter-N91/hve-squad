---
bump: patch
type: Fixed
---

- **Benchmark acceptance and evidence validation no longer admit misleading successes.** Rejection probes require natural rejection rather than watchdog termination; records reject noncanonical trial UUIDs that could disguise duplicate or reused observations, and native six-run result import selects the complete candidate arm without fabricated controls (`tests/tier2/live-benchmark/Test-EfficiencyTask.ps1`, `BenchmarkResults.psm1`).
- **Measurement reports distinguish document quality from software quality and define their timing boundaries.** Validated offline study evidence supports repeatability and external-rating analysis without claiming expert calibration (`tests/tier2/live-benchmark/BenchmarkStudy.psm1`).
- **The efficiency wizard provisions pinned Python tests with standard venv and pip**, and resumed runs receive the full workflow allowance from initialization while reserving independent-judge consumption and tracking cumulative native spending (`tests/tier2/live-benchmark/Start-EfficiencyWizard.ps1`, `Invoke-EfficiencyExercise.ps1`, `EfficiencyBenchmark.psm1`).
- **Numeric trial allowances avoid credential-parameter false positives without suppressing analysis or changing limits.** Baseline collection measures unmodified Squad source; benchmark-driven Scribe optimizations and dependent assertions are removed while native preparation, observational collection and independent quality gates remain. Modified-source observations stay separate historical evidence (`tests/tier2/live-benchmark/EfficiencyBenchmark.Tests.ps1`, `EfficiencyBenchmark.psm1`).
