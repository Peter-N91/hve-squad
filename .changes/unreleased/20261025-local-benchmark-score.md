---
bump: patch
type: Added
---

- **Benchmarking a branch is one command, and pull requests show how the score compares.** `Invoke-Benchmark.ps1 [-Runs 1..3]` runs the cold-start benchmark against the current checkout (about 300 credits and 20 minutes per run) and saves `score.json`, `badge.svg` and `report.md` in `benchmarks/efficiency/` for the branch to commit. The new Benchmark score pull request comment shows that score beside the base branch's, warns about lower scores and failed runs, shows the current score alone when the two cannot be compared, and never fails the pull request. The initial score was converted from the recorded three-run series `run-20261021-102320-92ef357d` (`tests/tier2/live-benchmark/Invoke-Benchmark.ps1`, `BenchmarkScore.psm1`, `Compare-Benchmark.ps1`, `.github/workflows/benchmark-score.yml`, `benchmarks/efficiency/README.md`).
