---
bump: patch
type: Fixed
---

- **A benchmark run could spend about 900 credits and end without saying why.** The requirements prompts drop the extra anchor, count and owner-role demands that let a PRD grow past the judge's 100,000-byte cap; a session that announces its final model call is recorded as `credit-limit` and the later steps are skipped; an unscored run says which stage ended and why the judge could not read the documents; and time the computer spends suspended no longer triggers the 3-hour timeout, while Windows is asked to stay awake during a run unless `-AllowSleep` is passed (`tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1`, `tests/tier2/live-benchmark/EfficiencyBenchmark.psm1`, `tests/tier2/live-benchmark/BenchmarkScore.psm1`, `tests/tier2/live-benchmark/Invoke-Benchmark.ps1`). The documented cost is now about 550 to 900 credits per run (`benchmarks/efficiency/README.md`).
