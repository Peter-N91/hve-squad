---
bump: patch
type: Fixed
---

- **Resumed efficiency runs no longer inherit a smaller initialization credit cap.** The benchmark supplies its full workflow allowance from the first CLI invocation, reserves independent judge credits, and monitors cumulative native spending across stages and recovery (`tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1`, `tests/tier2/live-benchmark/EfficiencyBenchmark.psm1`).
