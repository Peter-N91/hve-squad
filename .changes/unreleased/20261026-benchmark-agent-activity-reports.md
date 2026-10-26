---
bump: patch
type: Added
---

- **Benchmark reports now show where model work is spent.** Automatically compare Scribe dispatches, requests, dispatch time and credits, Coordinator requests and BRD/PRD author requests using native telemetry, with unavailable cells for older or incomplete evidence (`tests/tier2/live-benchmark/BenchmarkScore.psm1`, `EfficiencyBenchmark.psm1`).
- **Long benchmark runs now show their progress.** Timestamped stage transitions, remaining planned steps and quiet-period heartbeats keep the console informative without streaming model output or changing benchmark outcomes (`tests/tier2/live-benchmark/Invoke-Benchmark.ps1`, `Invoke-EfficiencyExercise.ps1`, `EfficiencyBenchmark.psm1`).
